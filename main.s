// main.s — Entry point for Moria C64/C128
//
// BASIC stub at $0801 with SYS entry.
// Saves BASIC ZP state, disables BASIC ROM, runs game,
// restores state and exits cleanly to BASIC.

// ============================================================
// BASIC stub — SYS 2062 ($080E)
// ============================================================
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
    lda $01
    ora #%00000001          // Set bit 0 (LORAM) — bank in BASIC ROM
    sta $01
    lda #$0e
    sta $d020               // Restore default border (light blue)
    lda #$06
    sta $d021               // Restore default background (blue)
    lda $d018
    ora #%00000010          // Lowercase mode (BASIC default)
    sta $d018
    lda #$93                // PETSCII clear screen
    jsr $ffd2               // KERNAL CHROUT
    rts                     // Return to BASIC

// All .text directives produce screen codes (not PETSCII) since
// all output uses direct screen RAM writes at $0400+.
.encoding "screencode_upper"

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
#import "player.s"
#import "ui_messages.s"
#import "ui_status.s"
#import "ui_character.s"
#import "ui_help.s"
#import "player_create.s"
#import "sound.s"
#import "dungeon_gen.s"
#import "dungeon_features.s"
#import "monster.s"
#import "tier_manager.s"
#import "monster_ai.s"
#import "monster_magic.s"
#import "item.s"
#import "player_items.s"
#import "spell_data.s"
#import "spell_effects.s"
#import "player_magic.s"
#import "ui_inventory.s"
#import "dungeon_render.s"
#import "dungeon_los.s"
#import "player_move.s"
#import "combat.s"
#import "monster_attack.s"
#import "turn.s"
#import "store.s"
#import "ui_store.s"
#import "save.s"
#import "score.s"
#import "title_screen.s"

// ============================================================
// Entry point
// ============================================================
entry_main:
    // Save BASIC's zero page state so we can restore on exit
    jsr save_zp

    // BASIC ROM already banked out by bootstrap above

    // Select unshifted character set (uppercase + graphics)
    // Bit 1 of $D018 selects character set: 0=uppercase, 1=lowercase
    lda $d018
    and #%11111101          // Clear bit 1 → uppercase + graphics
    sta $d018
    // Also set via $D016 to ensure proper state
    // (Actually $D018 bit 1 is sufficient on C64)

    // Set border and background to black
    lda #COL_BLACK
    sta $d020               // Border
    sta $d021               // Background

    // --- Initialize subsystems ---
    jsr detect_machine
    jsr reu_detect
    jsr tier_init
    jsr sound_init
    jsr rng_seed

    // Set default text color
    lda #COL_LGREY
    sta zp_text_color

    // Clear screen and display title
    jsr screen_clear
    jsr title_load_and_draw

    // Show REU status on title screen (row 12) if detected
    lda reu_present
    beq !no_reu_display+
    lda #12
    sta zp_cursor_row
    lda #13                     // Center: (40 - 14) / 2 = 13
    sta zp_cursor_col
    lda #COL_DGREY
    sta zp_text_color
    lda #<reu_status_str
    sta zp_ptr0
    lda #>reu_status_str
    sta zp_ptr0_hi
    jsr screen_put_string       // "REU: "
    lda reu_size_kb
    sta zp_temp0
    lda reu_size_kb + 1
    sta zp_temp1
    jsr screen_put_decimal_16   // Print KB value
    lda #<reu_kb_str
    sta zp_ptr0
    lda #>reu_kb_str
    sta zp_ptr0_hi
    jsr screen_put_string       // "KB DETECTED"
!no_reu_display:

    // Check for existing save file
    jsr check_savefile_exists
    bcc !no_save_exists+

    // --- Save exists: show New/Load menu ---
    lda #COL_WHITE
    sta zp_text_color
    lda #17
    sta zp_cursor_row
    lda #9                  // Center: (40-22)/2 = 9
    sta zp_cursor_col
    lda #<save_newgame_str
    sta zp_ptr0
    lda #>save_newgame_str
    sta zp_ptr0_hi
    jsr screen_put_string

!title_menu_loop:
    jsr input_get_key
    cmp #$4e                // 'N' — new game
    beq !title_new+
    cmp #$4c                // 'L' — load game
    beq !title_load+
    jmp !title_menu_loop-

!title_load:
    jsr rng_seed
    lda #SFX_PICKUP
    jsr sound_play
    jsr msg_init
    jsr load_game
    bcc !title_load_fail+
    jmp load_resume_game
!title_load_fail:
    // Load failed — fall through to new game
    jmp !title_new+

!no_save_exists:
    // --- No save: "PRESS ANY KEY" ---
    lda #COL_WHITE
    sta zp_text_color
    lda #17
    sta zp_cursor_row
    lda #13                 // Center: (40-14)/2 = 13
    sta zp_cursor_col
    lda #<press_key_str
    sta zp_ptr0
    lda #>press_key_str
    sta zp_ptr0_hi
    jsr screen_put_string

    jsr input_get_key

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

    // --- Character creation ---
    jsr player_create

    // --- Starting equipment ---
    // Wooden torch (type 13) in EQUIP_LIGHT with 40 charges
    lda #13
    sta inv_item_id + EQUIP_LIGHT
    lda #1
    sta inv_qty + EQUIP_LIGHT
    lda #40
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
    jsr store_init_all

    // --- Main game loop ---
    // Initialize dungeon level and generate map (new game only)
    lda #0
    sta zp_player_dlvl
    sta player_data + PL_DLEVEL
    sta player_data + PL_MAX_DLVL
    sta level_entry_dir
    lda #$ff
    sta zp_run_dir              // Not running
    jsr level_generate
    jsr monster_spawn_level
    jsr item_spawn_level
    jsr update_visibility       // Reveal starting area

    // Re-init SID after lengthy init sequence (defensive — ensures volume is set)
    jsr sound_init

    // Clear screen and do initial render
    jsr screen_clear
    jsr viewport_update
    jsr render_viewport
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
    jsr save_game
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
    jsr ui_char_display
    jsr input_get_key
    // Redraw map on return
    jsr screen_clear
    jsr viewport_update
    jsr render_viewport
    jsr status_draw
    jmp !main_loop-
!not_char:

    // Help?
    cmp #CMD_HELP
    bne !not_help+
    jsr ui_help_display
    jsr input_get_key
    // Redraw map on return — clear all rows then redraw
    lda #COL_BLACK
    sta zp_text_color
    jsr ui_help_clear_all
    jsr viewport_update
    jsr render_viewport
    jsr status_draw
    jmp !main_loop-
!not_help:

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
    jsr store_enter
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
    jsr tier_check_transition   // Load new tier if crossing boundary
    lda #0
    sta level_entry_dir         // 0 = descended
    lda #$ff
    sta zp_run_dir              // Stop running on level change
    jsr level_generate
    jsr monster_spawn_level
    jsr item_spawn_level
    jsr update_visibility
    jsr screen_clear
    jsr viewport_update
    jsr render_viewport
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
    jsr store_restock_all
!not_entering_town:
    jsr tier_check_transition   // Load new tier if crossing boundary
    lda #1
    sta level_entry_dir         // 1 = ascended
    lda #$ff
    sta zp_run_dir              // Stop running on level change
    jsr level_generate
    jsr monster_spawn_level
    jsr item_spawn_level
    jsr update_visibility
    jsr screen_clear
    jsr viewport_update
    jsr render_viewport
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
    jsr viewport_update
    jsr render_viewport
    jsr status_draw
    jmp !main_loop-
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
    jsr viewport_update
    jsr render_viewport
    jsr status_draw
    jmp !main_loop-
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
    jsr viewport_update
    jsr render_viewport
    jsr status_draw
    jmp !main_loop-
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
    jsr viewport_update
    jsr render_viewport
    jsr status_draw
    jmp !main_loop-
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
    jsr viewport_update
    jsr render_viewport
    jsr status_draw
    jmp !main_loop-
!drop_no_turn:
    jmp !main_loop-
!not_drop:

    // Inventory? (display only, no turn consumed)
    cmp #CMD_INVENTORY
    bne !not_inventory+
    jsr ui_inv_display
    jsr input_get_key
    // Redraw map on return
    lda #COL_BLACK
    sta zp_text_color
    jsr ui_help_clear_all
    jsr viewport_update
    jsr render_viewport
    jsr status_draw
    jmp !main_loop-
!not_inventory:

    // Equipment? (display only, no turn consumed)
    cmp #CMD_EQUIPMENT
    bne !not_equipment+
    jsr ui_equip_display
    jsr input_get_key
    // Redraw map on return
    lda #COL_BLACK
    sta zp_text_color
    jsr ui_help_clear_all
    jsr viewport_update
    jsr render_viewport
    jsr status_draw
    jmp !main_loop-
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
    jsr viewport_update
    jsr render_viewport
    jsr status_draw
    jmp !main_loop-
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
    jsr viewport_update
    jsr render_viewport
    jsr status_draw
    jmp !main_loop-
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
    jsr viewport_update
    jsr render_viewport
    jsr status_draw
    jmp !main_loop-
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
    jsr viewport_update
    jsr render_viewport
    jsr status_draw
    jmp !main_loop-
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
    jsr viewport_update
    jsr render_viewport
    jsr status_draw
    jmp !main_loop-
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
    jsr viewport_update
    jsr render_viewport
    jsr status_draw
    jmp !main_loop-
!cast_no_turn:
    // Restore screen after spell list overlay
    jsr screen_clear
    jsr viewport_update
    jsr render_viewport
    jsr status_draw
    jmp !main_loop-
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
    jsr viewport_update
    jsr render_viewport
    jsr status_draw
    jmp !main_loop-
!pray_no_turn:
    jsr screen_clear
    jsr viewport_update
    jsr render_viewport
    jsr status_draw
    jmp !main_loop-
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
    jsr viewport_update
    jsr render_viewport
    jsr status_draw
    jmp !main_loop-

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
    jsr delete_savefile
    jsr player_sync_from_zp
    jsr score_calculate
    jsr hiscore_load
    jsr hiscore_insert
    sta score_new_rank
    jsr hiscore_save
    jsr score_death_screen
    jsr input_get_key
    jmp !quit+

!quit:

    // --- Clean exit to BASIC ---
exit:
    jmp exit_trampoline     // Must run from below $A000 (banks in BASIC ROM)

// ============================================================
// String data (screen codes via .encoding "screencode_upper")
// ============================================================

title_str:
    .text "MORIA C=64" ; .byte 0

press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

reu_status_str:
    .text "REU: " ; .byte 0
reu_kb_str:
    .text "KB DETECTED" ; .byte 0

welcome_str:
    .text "WELCOME TO MORIA! SHIFT+Q TO QUIT." ; .byte 0

descend_str:
    .text "YOU DESCEND THE STAIRCASE." ; .byte 0

ascend_str:
    .text "YOU ASCEND THE STAIRCASE." ; .byte 0

at_surface_str:
    .text "YOU ARE ALREADY AT THE SURFACE." ; .byte 0

no_stairs_str:
    .text "YOU SEE NO STAIRS HERE." ; .byte 0

slain_str:
    .text "YOU HAVE BEEN SLAIN." ; .byte 0

// Safety: ensure assembled code doesn't overlap runtime data areas
program_end:
.assert "Program fits below CREATURE_BASE", program_end <= CREATURE_BASE, true
