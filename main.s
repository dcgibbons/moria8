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
#import "player_create.s"
#import "sound.s"
#import "dungeon_gen.s"
#import "dungeon_render.s"
#import "dungeon_los.s"
#import "player_move.s"
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

    // --- Main game loop (Phase 3: Town level) ---
    // Generate the town map
    jsr town_generate

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

    // Try to move
    jsr player_try_move
    bcc !move_blocked+

    // Move succeeded
    jsr msg_clear
    jsr viewport_update

    // Did viewport scroll?
    lda zp_view_x
    cmp old_view_x
    bne !full_redraw+
    lda zp_view_y
    cmp old_view_y
    bne !full_redraw+

    // No scroll — dirty render: redraw old tile and new tile only
    lda old_player_x
    sta zp_temp0
    lda old_player_y
    sta zp_temp1
    jsr render_single_tile
    lda zp_player_x
    sta zp_temp0
    lda zp_player_y
    sta zp_temp1
    jsr render_single_tile
    jmp !post_move+

!full_redraw:
    jsr render_viewport

!post_move:
    jsr turn_post_action
    jsr status_draw
    jmp !main_loop-

!move_blocked:
    // Bump sound already played by player_try_move
    jmp !main_loop-
!not_move:

    // Stairs down?
    cmp #CMD_STAIRS_DN
    bne !not_stairs+
    jsr check_stairs_at_player
    cmp #9                  // Stairs down type
    bne !no_stairs_here+
    lda #<stairs_str
    sta zp_ptr0
    lda #>stairs_str
    sta zp_ptr0_hi
    jsr msg_print
    jmp !main_loop-
!no_stairs_here:
    lda #<no_stairs_str
    sta zp_ptr0
    lda #>no_stairs_str
    sta zp_ptr0_hi
    jsr msg_print
    jmp !main_loop-
!not_stairs:

    // Rest?
    cmp #CMD_REST
    bne !not_rest+
    jsr msg_clear
    jsr turn_post_action
    jsr status_draw
    jmp !main_loop-
!not_rest:

    // Unknown command — ignore
    jmp !main_loop-
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

stairs_str:
    .text "THE STAIRS LEAD DOWN INTO DARKNESS..." ; .byte 0

no_stairs_str:
    .text "YOU SEE NO STAIRS HERE." ; .byte 0
