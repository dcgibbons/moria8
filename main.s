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
#import "turn.s"
#import "sound.s"

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

    // --- Main game loop ---
    // After character creation, show status bar and wait for commands.
    // Full dungeon loop starts in Phase 3.
    jsr screen_clear
    jsr status_draw

    // Show instructions on message line
    lda #<ready_str
    sta zp_ptr0
    lda #>ready_str
    sta zp_ptr0_hi
    jsr msg_print

!main_loop:
    jsr input_get_key
    cmp #$51                // 'Q' in PETSCII — quit
    beq !quit+
    cmp #$43                // 'C' in PETSCII — character sheet
    bne !not_char+
    jsr ui_char_display
    jsr input_get_key
    jsr screen_clear
    jsr status_draw
    lda #<ready_str
    sta zp_ptr0
    lda #>ready_str
    sta zp_ptr0_hi
    jsr msg_print
!not_char:
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
// String data (screen codes, null-terminated)
// ============================================================

// Screen code conversion: A=01, B=02, ... Z=1A, space=20,
// 0=30, 1=31, etc. Punctuation in $20-$3F range same as PETSCII.

title_str:
    // "MORIA C=64"
    .byte $0d, $0f, $12, $09, $01   // MORIA
    .byte $20                       // space
    .byte $03, $3d, $36, $34        // C=64
    .byte $00                       // null terminator

press_key_str:
    // "PRESS ANY KEY"
    .byte $10, $12, $05, $13, $13   // PRESS
    .byte $20                       // space
    .byte $01, $0e, $19             // ANY
    .byte $20                       // space
    .byte $0b, $05, $19             // KEY
    .byte $00

ready_str:
    // "READY. PRESS Q TO QUIT."
    .byte $12, $05, $01, $04, $19   // READY
    .byte $2e, $20                  // . (space)
    .byte $10, $12, $05, $13, $13   // PRESS
    .byte $20                       // space
    .byte $11                       // Q
    .byte $20                       // space
    .byte $14, $0f                  // TO
    .byte $20                       // space
    .byte $11, $15, $09, $14        // QUIT
    .byte $2e                       // .
    .byte $00
