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

// All .text directives produce screen codes (not PETSCII) since
// all output uses direct screen RAM writes at $0400+.
.encoding "screencode_upper"

#import "zeropage.s"
#import "memory.s"
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
#import "monster_ai.s"
#import "item.s"
#import "player_items.s"
#import "spell_effects.s"
#import "ui_inventory.s"
#import "dungeon_render.s"
#import "dungeon_los.s"
#import "player_move.s"
#import "combat.s"
#import "monster_attack.s"
#import "turn.s"

// ============================================================
// Entry point
// ============================================================
entry:
    // Save BASIC's zero page state so we can restore on exit
    jsr save_zp

    // Disable BASIC ROM — exposes RAM at $A000–$BFFF
    :BankOutBasic()

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
    jsr sound_init
    jsr rng_seed

    // Set default text color
    lda #COL_LGREY
    sta zp_text_color

    // Clear screen
    jsr screen_clear

    // --- Display title ---
    // "MORIA" in screen codes (M=0d, O=0f, R=12, I=09, A=01)
    lda #0
    sta zp_cursor_col
    lda #10
    sta zp_cursor_row
    lda #COL_WHITE
    sta zp_text_color
    lda #<title_str
    sta zp_ptr0
    lda #>title_str
    sta zp_ptr0_hi
    lda #15                 // Center: (40-10)/2 = 15
    sta zp_cursor_col
    jsr screen_put_string

    // "PRESS ANY KEY" prompt
    lda #COL_LGREY
    sta zp_text_color
    lda #12
    sta zp_cursor_row
    lda #12                 // Center: (40-16)/2 = 12
    sta zp_cursor_col
    lda #<press_key_str
    sta zp_ptr0
    lda #>press_key_str
    sta zp_ptr0_hi
    jsr screen_put_string

    // Wait for keypress (adds entropy to RNG seed from timing)
    jsr input_get_key

    // Re-seed RNG after user input for better entropy
    jsr rng_seed

    // Play sound as acknowledgment
    lda #SFX_PICKUP
    jsr sound_play

    // Initialize message system
    jsr msg_init

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

    // Ration of food (type 15) in carried slot 0
    lda #15
    sta inv_item_id
    lda #1
    sta inv_qty
    lda #0
    sta inv_p1
    sta inv_flags

    // Randomize item identification (shuffle potion/scroll/ring descriptors)
    jsr item_init_identification

    // --- Main game loop ---
    // Initialize dungeon level and generate map
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

    // Move or attack succeeded
    jsr trap_check_at_player
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
    jsr turn_post_action
    lda zp_game_flags
    and #$01
    beq !not_dead+
    jmp !player_died+
!not_dead:
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
    jsr viewport_update
    jsr render_viewport
    jsr turn_post_action
    lda zp_game_flags
    and #$01
    beq !not_dead+
    jmp !player_died+
!not_dead:
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
    jsr viewport_update
    jsr render_viewport
    jsr turn_post_action
    lda zp_game_flags
    and #$01
    beq !not_dead+
    jmp !player_died+
!not_dead:
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
    jsr viewport_update
    jsr render_viewport
    jsr turn_post_action
    lda zp_game_flags
    and #$01
    beq !not_dead+
    jmp !player_died+
!not_dead:
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
    jsr viewport_update
    jsr render_viewport
    jsr turn_post_action
    lda zp_game_flags
    and #$01
    beq !not_dead+
    jmp !player_died+
!not_dead:
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
    jsr viewport_update
    jsr render_viewport
    jsr turn_post_action
    lda zp_game_flags
    and #$01
    beq !not_dead+
    jmp !player_died+
!not_dead:
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
    jsr viewport_update
    jsr render_viewport
    jsr turn_post_action
    lda zp_game_flags
    and #$01
    beq !not_dead+
    jmp !player_died+
!not_dead:
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
    jsr viewport_update
    jsr render_viewport
    jsr turn_post_action
    lda zp_game_flags
    and #$01
    beq !not_dead+
    jmp !player_died+
!not_dead:
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
    jsr update_visibility
    jsr viewport_update
    jsr render_viewport
    jsr turn_post_action
    lda zp_game_flags
    and #$01
    beq !not_dead+
    jmp !player_died+
!not_dead:
    jsr status_draw
    jmp !main_loop-
!read_no_turn:
    jmp !main_loop-
!not_read:

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

    // Continue running → render + turn
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
    jsr turn_post_action
    lda zp_game_flags
    and #$01
    beq !not_dead+
    jmp !player_died+
!not_dead:
    jsr status_draw
    jmp !main_loop-

!run_blocked:
    lda #$ff
    sta zp_run_dir
    jmp !main_loop-

!run_trap_stop:
    lda #$ff
    sta zp_run_dir
    jsr update_visibility
    jsr viewport_update
    jsr render_viewport
    jsr turn_post_action
    lda zp_game_flags
    and #$01
    beq !not_dead+
    jmp !player_died+
!not_dead:
    jsr status_draw
    jmp !main_loop-

!run_stop_move:
    lda #$ff
    sta zp_run_dir
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
    jsr turn_post_action
    lda zp_game_flags
    and #$01
    beq !not_dead+
    jmp !player_died+
!not_dead:
    jsr status_draw
    jmp !main_loop-

!player_died:
    // Death screen
    jsr screen_clear
    lda #10
    sta zp_cursor_row
    lda #10
    sta zp_cursor_col
    lda #COL_RED
    sta zp_text_color
    lda #<mat_dead_str
    sta zp_ptr0
    lda #>mat_dead_str
    sta zp_ptr0_hi
    jsr screen_put_string
    jsr input_get_key
    jmp !quit+

!quit:

    // --- Clean exit to BASIC ---
exit:
    // Silence SID
    lda #0
    sta SID_VOLUME

    // Restore BASIC ROM
    :BankInBasic()

    // Restore saved zero page
    jsr restore_zp

    // Restore default screen colors
    lda #$0e                // Light blue (C64 default border)
    sta $d020
    lda #$06                // Blue (C64 default background)
    sta $d021

    // Restore default character set
    lda $d018
    ora #%00000010          // Set bit 1 → lowercase mode (BASIC default)
    sta $d018

    // Clear screen via KERNAL
    lda #$93                // PETSCII clear screen
    jsr $ffd2               // KERNAL CHROUT

    // Return to BASIC
    rts

// ============================================================
// String data (screen codes via .encoding "screencode_upper")
// ============================================================

title_str:
    .text "MORIA C=64" ; .byte 0

press_key_str:
    .text "PRESS ANY KEY" ; .byte 0

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
