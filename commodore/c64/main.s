// main.s — Entry point for Moria8 C64/C128
//
// BASIC stub at $0801 with SYS entry.
// Saves BASIC ZP state, disables BASIC ROM, runs game,
// restores state and exits cleanly to BASIC.

// ============================================================
// BASIC stub — SYS 2062 ($080E)
// ============================================================
// Overlay segments: produce separate PRGs at $E000.
// Assembled in same pass as main program — full symbol access.
// Only ONE overlay is active at a time (they share $E000-$EFFF).
.segmentdef StartupOverlay    [outPrg="out/ovl.start", start=$e000, min=$e000, max=$efff]
.segmentdef TownOverlay       [outPrg="out/ovl.town",  start=$e000, min=$e000, max=$efff]
.segmentdef DeathOverlay      [outPrg="out/ovl.death", start=$e000, min=$e000, max=$efff]
.segmentdef DungeonGenOverlay [outPrg="out/ovl.gen",   start=$e000, min=$e000, max=$efff]

.pc = $0801 "BASIC Stub"
:BasicUpstart2(entry)

// ============================================================
// Imports — order matters: labels must be defined before use
// ============================================================
.pc = $080e "Program"

// Bootstrap — MUST live below $A000 so BASIC's SYS can reach it
// before BASIC ROM is banked out.
entry:
    lda #$36                // Bank out BASIC ROM (keep KERNAL + I/O)
    sta $01
    jmp entry_main          // Now code past $A000 is accessible

// Exit trampoline — MUST live below $A000 because it banks BASIC
// ROM back in. If this ran from $A000+ the CPU would start executing
// BASIC ROM the instant we set bit 0 of $01.
exit_trampoline:
    lda #0
    sta $d418               // Silence SID
    jsr restore_zp          // Must run BEFORE banking BASIC in (buffer may be under BASIC ROM)
    sei
    // Restore default IRQ vector — our handler (irq_no_blink) is in the
    // $A000-$BFFF region, hidden once BASIC ROM is banked in.
    lda #$31
    sta $0314
    lda #$ea
    sta $0315
    lda $01
    ora #%00000001          // Set bit 0 (LORAM) — bank in BASIC ROM
    sta $01
    cli
    lda #$0e
    sta $d020               // Restore default border (light blue)
    lda #$06
    sta $d021               // Restore default background (blue)
    lda $d018
    ora #%00000010          // Lowercase mode (BASIC default)
    sta $d018
    lda $dd00
    ora #%00000011          // Restore VIC-II bank 0 (serial I/O may have corrupted)
    sta $dd00
    lda #$93                // PETSCII clear screen
    jsr $ffd2               // KERNAL CHROUT
    jmp ($a002)             // BASIC warm-start (works for both SYS and chain-load)

// All .text directives produce screen codes (not PETSCII) since
// all output uses direct screen RAM writes at $0400+.
.encoding "screencode_mixed"

#import "zeropage.s"
#import "memory.s"
#import "reu.s"
#import "screen.s"
#import "color.s"
#import "config.s"
#import "input.s"
#import "rng.s"
#import "math.s"
#import "tables.s"
#import "item_defs.s"
#import "player.s"
#import "ui_messages.s"
#import "ui_status.s"
#import "stat_display.s"
#import "sound.s"
#import "huffman.s"
#import "dungeon_data.s"
#import "dungeon_features.s"
#import "monster.s"
#import "tier_manager.s"
#import "overlay.s"
#import "monster_ai.s"
#import "recall.s"
#import "monster_magic.s"
#import "item.s"
#import "player_items.s"
#import "spell_data.s"
#import "spell_effects.s"
#import "player_magic.s"
#import "dungeon_render.s"
#import "dungeon_los.s"
#import "player_move.s"
#import "combat.s"
#import "projectile.s"
#import "ranged_fire.s"
#import "throw.s"
#import "bash.s"
#import "tunnel.s"
#import "monster_attack.s"
#import "turn.s"
#import "store_data.s"
#import "string_bank.s"
#import "save.s"
#import "disk_swap.s"
#import "score_io.s"
#import "title_screen.s"

// ============================================================
// Entry point
// ============================================================
entry_main:
    // Save BASIC's zero page state so we can restore on exit
    jsr save_zp

    // BASIC ROM already banked out by bootstrap above

    // Copy banked code payload to $F000 (must happen before any
    // trampoline calls — payload stored inline after program code)
    jsr init_copy_banked

    // Patch reu_show_status: RTS → JMP tramp_reu_show_status
    lda #$4c                    // JMP absolute opcode
    sta reu_show_status
    lda #<tramp_reu_show_status
    sta reu_show_status + 1
    lda #>tramp_reu_show_status
    sta reu_show_status + 2

    // Select lowercase/uppercase character set (52 letter symbols)
    // Bit 1 of $D018 selects character set: 0=uppercase+graphics, 1=lowercase+uppercase
    lda $d018
    ora #%00000010          // Set bit 1 → lowercase + uppercase
    sta $d018
    // Also set via $D016 to ensure proper state
    // (Actually $D018 bit 1 is sufficient on C64)

    // Set border and background to black
    lda #COL_BLACK
    sta $d020               // Border
    sta $d021               // Background

restart_entry:
    // --- Initialize subsystems ---
    jsr detect_machine
    jsr reu_detect
    jsr tier_init
    jsr sound_init
    jsr rng_seed

    // Install IRQ wedge: suppress KERNAL cursor blink permanently.
    // KERNAL routines (CHROUT, LOAD) constantly reset $CC=0 which
    // re-enables cursor blink. Our wedge forces $CC non-zero on every
    // IRQ tick BEFORE the KERNAL handler checks it, so the blink code
    // never executes and never corrupts color RAM.
    sei
    lda #<irq_no_blink
    sta $0314
    lda #>irq_no_blink
    sta $0315
    cli

    // Set default text color
    lda #COL_LGREY
    sta zp_text_color

    // Clear screen now so stale status bar (rows 21–23) from any prior session
    // is gone before KERNAL LOAD starts printing "SEARCHING...".
    // title_load_and_draw also clears after KERNAL LOAD to remove those messages.
    jsr screen_clear

    // Load and display title (clears screen internally after KERNAL LOAD)
    jsr title_load_and_draw

    // Explicitly clear status rows 21–23 before sysinfo draws on row 23.
    // title_load_and_draw + KERNAL LOAD together may leave stale status bar
    // data in those rows (e.g. from title_render_data parsing MAP_BASE).
    lda #STATUS_ROW             // row 21
    jsr screen_clear_row
    lda #STATUS_ROW + 1         // row 22
    jsr screen_clear_row
    lda #STATUS_ROW + 2         // row 23
    jsr screen_clear_row

    // Show system info on row 23 (machine type, KERNAL rev, REU)
    jsr title_show_sysinfo

    // --- Show title menu: N)EW  L)OAD  D)UAL DISK ---
    lda #COL_WHITE
    sta zp_text_color
    lda #17
    sta zp_cursor_row
    lda #8                  // Center: (40-23)/2 ≈ 8
    sta zp_cursor_col
    lda #<title_menu_str
    sta zp_ptr0
    lda #>title_menu_str
    sta zp_ptr0_hi
    jsr screen_put_string

!title_menu_loop:
    jsr input_get_key
    cmp #$4e                // 'N' — new game
    bne !not_n+
    jmp !title_new+
!not_n:
    cmp #$4c                // 'L' — load game
    bne !not_l+
    jmp !title_load+
!not_l:
    cmp #$44                // 'D' — disk setup sub-menu
    bne !title_menu_loop-

disk_menu_show:
    // Show disk sub-menu on row 18
    lda #18
    jsr screen_clear_row
    lda #COL_WHITE
    sta zp_text_color
    lda #18
    sta zp_cursor_row
    lda #9                  // Center: (40-22)/2 = 9
    sta zp_cursor_col
    lda #<ds_menu_str
    sta zp_ptr0
    lda #>ds_menu_str
    sta zp_ptr0_hi
    jsr screen_put_string

!disk_menu_loop:
    jsr input_get_key
    cmp #$53                // 'S' — same disk (mode 0)
    beq !disk_same+
    cmp #$57                // 'W' — swap disks (mode 1)
    beq !disk_swap+
    cmp #$23                // '#' — custom drive number (mode 2)
    beq !disk_drv9+
    jmp !disk_menu_loop-

!disk_same:
    lda #0
    sta disk_mode
    lda #8
    sta save_device
    lda #18
    jsr screen_clear_row
    jmp !title_menu_loop-

!disk_swap:
    lda #1
    sta disk_mode
    lda #8
    sta save_device
    jmp !disk_show_indicator+

!disk_drv9:
    jsr disk_enter_device
    bcs !disk_drv9_fail+        // fail — re-show disk sub-menu
    jmp !title_menu_loop-       // success — device configured
!disk_drv9_fail:
    jmp disk_menu_show

!disk_show_indicator:
    // Show "[Save Disk]" indicator on row 18
    lda #18
    jsr screen_clear_row
    lda #COL_CYAN
    sta zp_text_color
    lda #18
    sta zp_cursor_row
    lda #14                 // Center: (40-11)/2 ≈ 14
    sta zp_cursor_col
    lda #<ds_dual_str
    sta zp_ptr0
    lda #>ds_dual_str
    sta zp_ptr0_hi
    jsr screen_put_string
    lda #COL_WHITE
    sta zp_text_color
    jmp !title_menu_loop-

!title_load:
    jsr rng_seed
    lda #SFX_PICKUP
    jsr sound_play
    jsr msg_init
    jsr disk_prompt_save        // Swap to save disk if dual
    jsr load_game
    bcc !title_load_fail+
    jsr disk_prompt_game        // Swap back for tier loading
    jmp load_resume_game
!title_load_fail:
    jsr disk_prompt_game        // Swap back even on failure
    jsr input_get_key           // Let user see error message from load_game
    jmp !title_menu_loop-       // Back to N/L/D menu (not character creation)

!title_new:
    // Re-seed RNG after user input for better entropy
    jsr rng_seed

    // Play sound as acknowledgment
    lda #SFX_PICKUP
    jsr sound_play

    // Initialize message system
    jsr msg_init

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
    lda $d011
    and #%11101111              // Clear bit 4 — DEN off
    sta $d011
    jsr screen_clear

    // Randomize item identification (shuffle potion/scroll/ring descriptors)
    jsr item_init_identification
    jsr tramp_store_init_all

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
    jsr overlay_load
    jsr tramp_level_generate
    jsr monster_spawn_level
    jsr item_spawn_level
    jsr update_visibility       // Reveal starting area

    // Re-init SID after lengthy init sequence (defensive — ensures volume is set)
    jsr sound_init

    // Clear screen and do initial render
    jsr screen_clear
    jsr viewport_update
    jsr render_viewport
    lda $d011
    ora #%00010000              // Set bit 4 — DEN on, show rendered screen
    sta $d011
    jsr status_draw

    // Welcome message
    lda #<welcome_str
    sta zp_ptr0
    lda #>welcome_str
    sta zp_ptr0_hi
    jsr msg_print

    jmp !main_loop+

// ============================================================
// load_resume_game — Entry point after successful load
// ============================================================
load_resume_game:
    // Load creature tier for the resumed dungeon level
    jsr tier_check_transition

    // Recalculate derived stats from loaded base values
    jsr player_calc_stats
    jsr player_calc_hp

    // Stop any running
    lda #$ff
    sta zp_run_dir

    // Re-init SID
    jsr sound_init

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

!main_loop:
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

    // Any keypress cancels running
    lda $c6                     // Keyboard buffer count
    bne !run_cancel+
    jmp run_step

!run_cancel:
    lda #0
    sta $c6                     // Flush keyboard buffer
    lda #$ff
    sta zp_run_dir
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
    jmp !main_loop-
!not_paralyzed:
    jsr input_get_command

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
    sta $c6                     // Clear keyboard buffer (prevent key repeat from dismissing)
    jsr input_get_key
    // Redraw map on return — clear all rows then redraw
    lda #COL_BLACK
    sta zp_text_color
    jsr ui_help_clear_all
    jmp vp_render_status_loop
!not_help:

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
    sta $c6                     // Clear keyboard buffer (prevent key repeat from dismissing)
    jsr input_get_key           // Wait for dismiss
!recall_done:
    jsr screen_clear
    jmp vp_render_status_loop
!not_recall:

    // Movement? (CMD_MOVE_N through CMD_MOVE_SE = $01-$08)
    cmp #CMD_MOVE_N
    bcc !not_move+
    cmp #CMD_MOVE_SE + 1
    bcs !not_move+

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
    jsr player_try_move
    bcc !move_blocked+

    // Move or attack succeeded — run AI before render so screen
    // reflects post-AI monster positions (BUG-17 fix)
    jsr trap_check_at_player
    jsr turn_post_action
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
    bne !full_redraw+
    lda zp_view_y
    cmp old_view_y
    bne !full_redraw+

    // Did a room get revealed?
    lda vis_room_revealed
    bne !full_redraw+

    // No scroll, no room reveal — render local area around old+new position
    jsr render_local_area
    jmp !post_move+

!full_redraw:
    jsr render_viewport

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
    jsr status_draw
    jmp !main_loop-

!move_blocked:
    // Bump sound already played by player_try_move
    jmp !main_loop-
!not_move:

    // Stairs down?
    cmp #CMD_STAIRS_DN
    bne !not_stairs_dn+
    jsr check_stairs_at_player
    cmp #9                  // Stairs down type
    bne !no_stairs_dn+
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
    lda $d011
    and #%11101111              // Blank screen (clear bit 4 — DEN)
    sta $d011
    jsr screen_clear            // Clear old level before lengthy load/generate
    jsr tier_check_transition   // Load new tier if crossing boundary
    lda #0
    sta level_entry_dir         // 0 = descended
    lda #$ff
    sta zp_run_dir              // Stop running on level change
    lda #OVL_DUNGEON_GEN
    jsr overlay_load
    jsr tramp_level_generate
    jsr monster_spawn_level
    jsr item_spawn_level
    jsr update_visibility
    jsr screen_clear
    jsr viewport_update
    jsr render_viewport
    lda $d011
    ora #%00010000              // Restore screen (set bit 4 — DEN)
    sta $d011
    jsr status_draw
    lda #<descend_str
    sta zp_ptr0
    lda #>descend_str
    sta zp_ptr0_hi
    jsr msg_print
    jmp !main_loop-
!no_stairs_dn:
    lda #<no_stairs_str
    sta zp_ptr0
    lda #>no_stairs_str
    sta zp_ptr0_hi
    jsr msg_print
    jmp !main_loop-
!not_stairs_dn:

    // Stairs up?
    cmp #CMD_STAIRS_UP
    bne !not_stairs_up+
    jsr check_stairs_at_player
    cmp #10                 // Stairs up type
    bne !no_stairs_up+
    // Ascend
    lda zp_player_dlvl
    beq !at_surface+
    dec zp_player_dlvl
    lda zp_player_dlvl
    sta player_data + PL_DLEVEL
    // Restock stores when returning to town
    bne !not_entering_town+
    jsr tramp_store_restock_all
!not_entering_town:
    lda $d011
    and #%11101111              // Blank screen (clear bit 4 — DEN)
    sta $d011
    jsr screen_clear            // Clear old level before lengthy load/generate
    jsr tier_check_transition   // Load new tier if crossing boundary
    lda #1
    sta level_entry_dir         // 1 = ascended
    lda #$ff
    sta zp_run_dir              // Stop running on level change
    lda #OVL_DUNGEON_GEN
    jsr overlay_load
    jsr tramp_level_generate
    jsr monster_spawn_level
    jsr item_spawn_level
    jsr update_visibility
    jsr screen_clear
    jsr viewport_update
    jsr render_viewport
    lda $d011
    ora #%00010000              // Restore screen (set bit 4 — DEN)
    sta $d011
    jsr status_draw
    lda #<ascend_str
    sta zp_ptr0
    lda #>ascend_str
    sta zp_ptr0_hi
    jsr msg_print
    jmp !main_loop-
!at_surface:
    lda #<at_surface_str
    sta zp_ptr0
    lda #>at_surface_str
    sta zp_ptr0_hi
    jsr msg_print
    jmp !main_loop-
!no_stairs_up:
    lda #<no_stairs_str
    sta zp_ptr0
    lda #>no_stairs_str
    sta zp_ptr0_hi
    jsr msg_print
    jmp !main_loop-
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
    jmp !main_loop-
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
    jmp !main_loop-
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
    jmp !main_loop-
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
    jmp !main_loop-
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
    jmp !main_loop-
!not_drop:

    // Inventory? (display only, no turn consumed)
    cmp #CMD_INVENTORY
    bne !not_inventory+
    lda #$ff
    sta uinv_filter             // Show all items
    jsr tramp_ui_inv_display
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
    jmp !main_loop-
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
    jmp !main_loop-
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
    jmp !main_loop-
!eat_no_turn:
    jmp !main_loop-
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
    jmp !main_loop-
!quaff_no_turn:
    jmp !main_loop-
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
    jmp !main_loop-
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
    jmp !main_loop-
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
    jmp !main_loop-
!not_use:

    // Cast spell?
    cmp #CMD_CAST
    bne !not_cast+
    jsr msg_clear
    jsr player_cast_spell
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
    jsr player_pray
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
    jmp !main_loop-
!gain_no_turn:
    jmp !main_loop-
!not_gain:

    // Fire ranged weapon?
    cmp #CMD_FIRE
    bne !not_fire+
    jsr msg_clear
    jsr ranged_fire
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
    jmp !main_loop-
!not_fire:

    // Throw item?
    cmp #CMD_THROW
    bne !not_throw+
    jsr msg_clear
    jsr throw_item
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
    jmp !main_loop-
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
    jmp !main_loop-
!refuel_no_turn:
    jmp !main_loop-
!not_refuel:

    // Bash?
    cmp #CMD_BASH
    bne !not_bash+
    jsr msg_clear
    jsr bash_command
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
    jmp !main_loop-
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
    jmp !main_loop-
!not_tunnel:

    // Look?
    cmp #CMD_LOOK
    bne !not_look+
    jsr msg_clear
    jsr do_look
    jmp !main_loop-
!not_look:

    // Running? (CMD_RUN_N through CMD_RUN_SE = $25-$2c)
    cmp #CMD_RUN_N
    bcc !not_run+
    cmp #CMD_RUN_SE + 1
    bcs !not_run+

    sec
    sbc #CMD_RUN_N              // Direction index 0-7
    sta zp_run_dir
    jmp run_step                // Take first step
!not_run:

    // Unknown command — ignore
    jmp !main_loop-

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
    lda (zp_ptr0),y
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
    jsr render_viewport

!run_post:
    jsr status_draw
    jmp !main_loop-

!run_blocked:
    lda #$ff
    sta zp_run_dir
    jmp !main_loop-

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
    jsr render_viewport
!rsm_post:
    jsr status_draw
    jmp !main_loop-

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
    jmp !main_loop-

// ============================================================
// IRQ wedge — suppress KERNAL cursor blink
// Forces $CC non-zero before KERNAL IRQ handler checks it.
// Must live in main RAM (always accessible during IRQ).
// ============================================================
irq_no_blink:
    lda #1
    sta $cc                 // Force non-zero (inc wraps $FF→$00, re-enabling blink)
    jmp $ea31               // Continue to standard KERNAL IRQ handler

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

// ============================================================
// Dungeon gen overlay trampoline — bank KERNAL out, call $E000 overlay
// ============================================================
// KERNAL must be off ($34) while executing overlay code at $E000.
// IRQs must stay DISABLED for the entire overlay execution:
//   - tramp_level_generate holds sei from entry to exit
//   - inner trampolines (tramp_assign_special_room, tramp_vault_seal_entrance,
//     verify_connectivity) use php/plp to preserve the caller's interrupt state
//     instead of cli, so IRQs remain disabled throughout dungeon generation
tramp_level_generate:
    sei
    lda #BANK_NO_ROMS           // $34 — KERNAL off, I/O on; $E000 = overlay RAM
    sta $01
    jsr level_generate          // executes from DungeonGenOverlay at $E000
    lda #BANK_NO_BASIC          // $36 — KERNAL back on; restore normal game banking
    sta $01
    cli
    rts

// ============================================================
// Special rooms trampolines — SEI + bank out KERNAL, call $F000+
// ============================================================
tramp_assign_special_room:
    php                         // Save interrupt state (caller may be in sei context)
    sei
    lda $01
    pha                         // Save caller's $01 (may be $34 if called from overlay)
    lda #BANK_NO_ROMS
    sta $01
    jsr assign_special_room
    pla
    sta $01                     // Restore caller's banking state
    plp                         // Restore interrupt state (no cli — would re-enable IRQs with $01=$34)
    rts

tramp_vault_seal_entrance:
    php                         // Save interrupt state (caller may be in sei context)
    sei
    lda $01
    pha                         // Save caller's $01 (may be $34 if called from overlay)
    lda #BANK_NO_ROMS
    sta $01
    jsr vault_seal_entrance
    pla
    sta $01                     // Restore caller's banking state
    plp                         // Restore interrupt state
    rts

tramp_spawn_special_room_monsters:
    sei
    lda #BANK_NO_ROMS
    sta $01
    jsr spawn_special_room_monsters
    jmp tramp_sr_epilogue

tramp_spawn_nest_gold:
    sei
    lda #BANK_NO_ROMS
    sta $01
    jsr spawn_nest_gold
    jmp tramp_sr_epilogue

tramp_find_special_room:
    pha                         // Save A (room type input)
    sei
    lda #BANK_NO_ROMS
    sta $01
    pla                         // Restore A
    jsr find_special_room
    // Carry flag preserved — lda/sta don't affect carry
    jmp tramp_sr_epilogue

tramp_sr_epilogue:
    lda #BANK_NO_BASIC
    sta $01
    cli
    rts

// ============================================================
// Ego item trampolines — SEI + bank out KERNAL, call $F000+
// ============================================================
tramp_roll_ego_type:
    pha                         // Save A (item type input)
    sei
    lda #BANK_NO_ROMS
    sta $01
    pla                         // Restore A
    jsr roll_ego_type
    pha                         // Save result
    lda #BANK_NO_BASIC
    sta $01
    cli
    pla                         // Restore result
    rts

// tramp_ego_append_suffix — Append ego suffix to combat_msg_buf
// Input: A = ego type
// Copies suffix string from $F000 region to combat_msg_buf while banked out.
// Clobbers: A, X, Y, zp_ptr0, zp_ptr1
tramp_ego_append_suffix:
    cmp #0
    beq !teas_done+             // No ego → nothing to append
    pha
    sei
    lda #BANK_NO_ROMS
    sta $01
    pla
    jsr ego_get_suffix_ptr      // zp_ptr0 = suffix string (in $F000)
    // Copy string to combat_msg_buf (while banked out so we can read $F000)
    ldx cmb_buf_idx
    ldy #0
!teas_loop:
    lda (zp_ptr0),y
    beq !teas_end+
    sta combat_msg_buf,x
    inx
    iny
    cpx #41                     // Buffer overflow protection
    bcs !teas_end+
    jmp !teas_loop-
!teas_end:
    stx cmb_buf_idx
    lda #BANK_NO_BASIC
    sta $01
    cli
!teas_done:
    rts

// tramp_ego_put_suffix — Write ego suffix directly to screen
// Input: A = ego type
// Uses screen_put_char to write each char while KERNAL banked out.
// Clobbers: A, X, Y, zp_ptr0
tramp_ego_put_suffix:
    cmp #0
    beq !teps_done+
    pha
    sei
    lda #BANK_NO_KERNAL         // $35 — I/O visible for color RAM
    sta $01
    pla
    jsr ego_get_suffix_ptr      // zp_ptr0 = suffix string (in $F000)
    // Read chars from $F000 and write to screen
    ldy #0
!teps_loop:
    lda (zp_ptr0),y
    beq !teps_end+
    sty teps_save_y
    jsr screen_put_char         // Clobbers Y
    ldy teps_save_y
    iny
    jmp !teps_loop-
!teps_end:
    lda #BANK_NO_BASIC
    sta $01
    cli
!teps_done:
    rts
teps_save_y: .byte 0

// ============================================================
// tramp_ego_apply_damage — Apply ego slay/bonus damage (banked at $F000)
// Input: A = ego type (1-7), cmb_damage and cmb_type set
// Output: cmb_damage updated
// Clobbers: A, X, Y, zp_math_a/b, zp_temp3, zp_temp4
tramp_ego_apply_damage:
    pha
    sei
    lda #BANK_NO_ROMS
    sta $01
    pla
    jsr ego_apply_damage
    lda #BANK_NO_BASIC
    sta $01
    cli
    rts

// tramp_ego_get_ac_bonus — Get ego AC bonus (banked at $F000)
// Input: A = ego type (1-7)
// Output: A = AC bonus (0 if none)
// Clobbers: X
tramp_ego_get_ac_bonus:
    pha
    sei
    lda #BANK_NO_ROMS
    sta $01
    pla
    jsr ego_get_ac_bonus
    pha
    lda #BANK_NO_BASIC
    sta $01
    cli
    pla
    rts

// tramp_dig_ability — Calculate digging ability
// Now in main RAM — no banking needed.
// Output: tun_dig_ability set
// Clobbers: A, X
tramp_dig_ability:
    jmp calc_dig_ability

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

// Init-only strings — kept in main RAM (small, referenced by title_screen.s)
// ============================================================
title_str:
    .text "MORIA8 C=64" ; .byte 0

// title_show_sysinfo — Trampoline to call banked version at $F000
// Reads KERNAL_REV while KERNAL is still banked in, then banks out.
title_show_sysinfo:
    lda KERNAL_REV              // Read from ROM while KERNAL banked in
    sta tsi_krev_cached
    sei
    lda #BANK_NO_KERNAL         // $35 — I/O visible for color RAM
    sta $01
    jsr title_show_sysinfo_banked
    lda #BANK_NO_BASIC
    sta $01
    cli
    rts
tsi_krev_cached: .byte 0

// tramp_reu_show_status — Bank out KERNAL to call banked status display
// Patched into reu_show_status at startup by init code.
tramp_reu_show_status:
    sei
    lda $01
    pha
    lda #BANK_NO_KERNAL         // $35 — I/O visible for screen writes
    sta $01
    jsr reu_show_status_banked
    pla
    sta $01
    cli
    rts

#import "ui_help_clear.s"

// ============================================================
// UI screen trampolines — SEI + bank out KERNAL, call $F000+
// ============================================================
tramp_ui_help_display:
    sei
    lda #BANK_NO_KERNAL       // $35 — I/O visible for color RAM writes
    sta $01
    jsr ui_help_display
    jmp tramp_sr_epilogue

tramp_ui_char_display:
    sei
    lda #BANK_NO_KERNAL       // $35 — I/O visible for color RAM writes
    sta $01
    jsr ui_char_display
    jmp tramp_sr_epilogue

tramp_ui_inv_display:
    sei
    lda #BANK_NO_KERNAL       // $35 — I/O visible for color RAM writes
    sta $01
    jsr ui_inv_display
    jmp tramp_sr_epilogue

tramp_ui_equip_display:
    sei
    lda #BANK_NO_KERNAL       // $35 — I/O visible for color RAM writes
    sta $01
    jsr ui_equip_display
    jmp tramp_sr_epilogue

tramp_ui_recall:
    sei
    lda #BANK_NO_KERNAL       // $35 — I/O visible for color RAM writes
    sta $01
    jsr ui_recall_display
    jmp tramp_sr_epilogue

// Recall command variables
recall_prompt_str: .text "Recall which? " ; .byte 0
recall_query_sc:   .byte 0             // Screen code of typed letter
recall_found_type: .byte 0             // Creature type index found
recall_last_sc:    .byte 0             // Screen code of last recall shown (0 = none)
recall_last_idx:   .byte 0             // Creature index last shown (for cycling)

// ============================================================
// Store overlay trampolines — load overlay, bank out KERNAL, call $E000+
// ============================================================
// Shared preamble: ensure town overlay is loaded, then bank out KERNAL
store_overlay_preamble:
    lda #OVL_TOWN
    jsr overlay_load
    sei
    lda #BANK_NO_KERNAL         // $35 — $E000 = RAM + I/O for color RAM
    sta $01
    rts

tramp_store_init_all:
    jsr store_overlay_preamble
    jsr store_init_all
    jmp tramp_sr_epilogue

tramp_store_restock_all:
    jsr store_overlay_preamble
    jsr store_restock_all
    jmp tramp_sr_epilogue

tramp_store_enter:
    jsr store_overlay_preamble
    jsr store_enter
    jmp tramp_sr_epilogue

// ============================================================
// Startup overlay trampoline — load overlay, bank out KERNAL, call $E000+
// ============================================================
tramp_player_create:
    lda #OVL_STARTUP
    jsr overlay_load
    sei
    lda #BANK_NO_KERNAL         // $35 — $E000 = RAM + I/O for color RAM
    sta $01
    jsr player_create
    jmp tramp_sr_epilogue

// ============================================================
// Death overlay trampoline — orchestrates the full game-over sequence
// ============================================================
// Interleaves overlay calls ($E000, $01=$34) with KERNAL I/O ($01=$36).
// Pre-resolves creature name before overlay overwrites tier data.
tramp_game_over:
    // 1. Resolve creature name while tier data still at $E000
    lda zp_death_source
    cmp #DEATH_CURSED           // Special sources ($FD-$FF) don't need name
    bcs !tgo_load_overlay+
    tax
    jsr creature_get_name       // Copies name to creature_name_buf in main RAM

!tgo_load_overlay:
    // 2. Load death overlay (replaces tier data at $E000)
    lda #OVL_DEATH
    jsr overlay_load

    // 3. Calculate score (overlay code, no KERNAL needed)
    sei
    lda #BANK_NO_ROMS
    sta $01
    jsr score_calculate
    lda #BANK_NO_BASIC
    sta $01
    cli

    // 4. Load high scores from disk (main RAM, needs KERNAL)
    jsr hiscore_load

    // 5. Insert into high score table (overlay code)
    sei
    lda #BANK_NO_ROMS
    sta $01
    jsr hiscore_insert
    lda #BANK_NO_BASIC
    sta $01
    cli

    // 6. Save high scores to disk (main RAM, needs KERNAL)
    jsr hiscore_save

    // 7. Display death screen (overlay code)
    // Defensive: restore VIC-II bank 0 after KERNAL serial I/O
    // KERNAL uses CIA2 ($DD00) bits 3-5 for serial bus;
    // bits 0-1 select VIC bank. Ensure bank 0 ($0000-$3FFF).
    lda $dd00
    ora #%00000011              // Bits 0-1 = %11 → bank 0
    sta $dd00
    sei
    lda #BANK_NO_KERNAL         // $35 — I/O visible for color RAM
    sta $01
    jsr score_death_screen
    lda #BANK_NO_BASIC
    sta $01
    cli
    rts

// Help screen string data — in main RAM (too large for $F000 banked region)
#import "ui_help_data.s"

// ============================================================
// game_over_prompt — R)EBOOT / S)TART OVER / Q)UIT prompt
// Shown at all exit points (save+quit, voluntary quit, death).
// Q falls through; R and S branch internally.
// ============================================================
game_over_prompt:
    jsr screen_clear
    lda #COL_WHITE
    sta zp_text_color
    lda #12                     // Row 12 (center)
    sta zp_cursor_row
    lda #9                      // Col 9: (40-22)/2 = 9
    sta zp_cursor_col
    lda #<game_over_str
    sta zp_ptr0
    lda #>game_over_str
    sta zp_ptr0_hi
    jsr screen_put_string
    lda #0
    sta $c6                     // Flush keyboard buffer
!gop_loop:
    jsr input_get_key
    cmp #$52                    // 'R' — reboot (reload from disk)
    beq !gop_reboot+
    cmp #$53                    // 'S' — start over (restart to title)
    beq !gop_restart+
    cmp #$51                    // 'Q' — quit to BASIC
    bne !gop_loop-
    rts                         // Q: fall through to exit_trampoline
!gop_reboot:
    // Hard reset — jump through the C64 cold-start vector.
    // KERNAL ROM is readable ($01=$36, HIRAM set), so $FFFC/$FFFD
    // contain the reset vector ($FCE2). Equivalent to pressing reset.
    jmp ($fffc)
!gop_restart:
    jmp game_restart

game_over_str:
    .text "R)EBOOT  S)TART  Q)UIT" ; .byte 0

// ============================================================
// game_restart — reset game state, return to title screen
// Clears mutable state (ZP vars, inventory, tier), then jumps
// to restart_entry (skipping one-time init_copy_banked etc.).
// ============================================================
game_restart:
    // Clear ZP game variables $2B–$8F (player stats, turn counter,
    // effect timers, monster counts, etc.)
    lda #0
    ldx #0
!clr_zp:
    sta $2b,x
    inx
    cpx #($8f - $2b + 1)        // 101 bytes
    bne !clr_zp-

    // Clear static game-state variables in data segments
    lda #0
    sta eff_fear_timer
    sta recall_query_sc
    sta recall_found_type
    sta recall_last_sc
    sta recall_last_idx

    // Clear inventory: inv_item_id[] = FI_EMPTY ($FF), qty/p1/flags = $00
    lda #$ff
    ldx #TOTAL_INV_SLOTS - 1
!clr_inv_id:
    sta inv_item_id,x
    dex
    bpl !clr_inv_id-

    lda #0
    ldx #TOTAL_INV_SLOTS - 1
!clr_inv_rest:
    sta inv_qty,x
    sta inv_p1,x
    sta inv_flags,x
    dex
    bpl !clr_inv_rest-

    // Reset tier state (zp_current_tier already zeroed above)
    sta current_tier
    sta tier_loaded

    jmp restart_entry

// Safety: ensure runtime code doesn't overlap runtime data areas
program_end:
.assert "Program fits below MAP_BASE", program_end <= MAP_BASE, true

// ============================================================
// Init-only code below — lives past CREATURE_BASE, safe because
// it runs once at startup before dungeon map or RLE workspace
// are used. Overwritten during normal gameplay.
// ============================================================

// init_copy_banked — Copy banked code payload to $F000
// Called once at startup before any $F000 trampoline is used.
// Clobbers: A, X, Y, zp_ptr0/hi, zp_ptr1/hi
init_copy_banked:
    sei
    lda #BANK_NO_ROMS           // $34 — bank out all ROMs to write $F000
    sta $01
    lda #<banked_payload
    sta zp_ptr0
    lda #>banked_payload
    sta zp_ptr0_hi
    lda #$00
    sta zp_ptr1
    lda #$F0
    sta zp_ptr1_hi
    ldx #((banked_payload_end - banked_payload + 255) / 256)
    ldy #0
!copy:
    lda (zp_ptr0),y
    sta (zp_ptr1),y
    iny
    bne !copy-
    inc zp_ptr0_hi
    inc zp_ptr1_hi
    dex
    bne !copy-
    lda #BANK_NO_BASIC          // $36 — restore normal banking
    sta $01
    cli
    rts

// ============================================================
// Banked code payload — stored inline here, copied to $F000
// at startup by init_copy_banked.
//
// Using .pseudopc so labels resolve to $F000+ addresses (where
// the code runs) but bytes are stored contiguously after the
// main program. This avoids spanning $D000 (I/O registers) in
// the PRG file, which would corrupt the serial bus during
// KERNAL LOAD from disk.
// ============================================================
banked_payload:
.pseudopc $F000 {
    #import "special_rooms.s"
    #import "ego_items.s"
    #import "title_sysinfo_banked.s"
    #import "reu_loading_banked.s"
    #import "ui_help.s"
    #import "ui_character.s"
    #import "ui_inventory.s"
    #import "ui_home.s"
    #import "string_bank_banked.s"
    #import "ui_recall.s"

banked_code_end:
}
banked_payload_end:

.print "Banked payload: " + (banked_payload_end - banked_payload) + " bytes at $" + toHexString(banked_payload) + "-$" + toHexString(banked_payload_end)
.assert "Payload fits below I/O ($D000)", banked_payload_end < $D000, true
.assert "Banked code fits below CPU vectors", banked_code_end <= $FFFA, true

// ============================================================
// Town overlay — store code at $E000, output to separate PRG
// ============================================================
// This segment produces out/ovl_town (loaded from disk as OVL.TOWN).
// Labels resolve to $E000+ but bytes go to the overlay PRG file,
// not the main moria.prg. All main RAM symbols are accessible.
.segment TownOverlay
    #import "store.s"
    #import "ui_store.s"
ovl_town_end:
.print "Town overlay: " + (ovl_town_end - $e000) + " bytes at $E000-$" + toHexString(ovl_town_end)
.assert "Town overlay fits in $E000-$EFFF", ovl_town_end <= $F000, true

// ============================================================
// Startup overlay — character creation at $E000, output to separate PRG
// ============================================================
// This segment produces out/ovl_start (loaded from disk as OVL.START).
// Used once during new game, then replaced by town/death overlays.
.segment StartupOverlay
    #import "background_data.s"
    #import "player_create.s"
ovl_start_end:
.print "Startup overlay: " + (ovl_start_end - $e000) + " bytes at $E000-$" + toHexString(ovl_start_end)
.assert "Startup overlay fits in $E000-$EFFF", ovl_start_end <= $F000, true

// ============================================================
// Death overlay — score + high score display at $E000
// ============================================================
// This segment produces out/ovl_death (loaded from disk as OVL.DEATH).
// Used once at game over. Contains scoring math, death screen display,
// and high score insertion/display. KERNAL I/O stays in score_io.s.
.segment DeathOverlay
    #import "score.s"
ovl_death_end:
.print "Death overlay: " + (ovl_death_end - $e000) + " bytes at $E000-$" + toHexString(ovl_death_end)
.assert "Death overlay fits in $E000-$EFFF", ovl_death_end <= $F000, true

// ============================================================
// Dungeon generation overlay — town + dungeon generation at $E000
// ============================================================
// This segment produces out/ovl.gen (loaded from disk as OVL.GEN).
// Loaded on demand whenever stairs are used or a new game starts.
// Shared constants and data tables stay in dungeon_data.s (main segment).
.segment DungeonGenOverlay
    #import "dungeon_gen.s"
ovl_gen_end:
.print "DungeonGen overlay: " + (ovl_gen_end - $e000) + " bytes at $E000-$" + toHexString(ovl_gen_end)
.assert "DungeonGen overlay fits in $E000-$EFFF", ovl_gen_end <= $F000, true
