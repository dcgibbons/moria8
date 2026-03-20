// input.s — Keyboard input and command parsing
//
// Uses KERNAL GETIN ($FFE4) to read keyboard buffer.
// Maps PETSCII key codes to internal command IDs.
// Supports vi-keys (HJKLYUBN) for 8-direction movement
// Numeric repeat prefixes are intentionally unimplemented.
// `zp_input_count` is currently fixed to 1 for all commands.
//
// Note: GETIN returns PETSCII codes. We convert to command IDs
// via a lookup table. The KERNAL IRQ handler must remain active
// for keyboard scanning to work.

// KERNAL vectors
.const KERNAL_GETIN = $ffe4

// Keyboard/CIA registers
.const KBDBUF_COUNT = $c6
.const CIA1_PORTA   = $dc00
.const CIA1_PORTB   = $dc01
.const CIA1_DDRA    = $dc02
.const CIA1_DDRB    = $dc03

// ============================================================
// Command IDs — internal constants, not key codes
// ============================================================
.const CMD_NONE      = $00  // No command / unknown key
.const CMD_MOVE_N    = $01  // Move north (up)
.const CMD_MOVE_S    = $02  // Move south (down)
.const CMD_MOVE_W    = $03  // Move west (left)
.const CMD_MOVE_E    = $04  // Move east (right)
.const CMD_MOVE_NW   = $05  // Move northwest
.const CMD_MOVE_NE   = $06  // Move northeast
.const CMD_MOVE_SW   = $07  // Move southwest
.const CMD_MOVE_SE   = $08  // Move southeast
.const CMD_STAIRS_DN = $09  // Go down stairs (>)
.const CMD_STAIRS_UP = $0a  // Go up stairs (<)
.const CMD_REST      = $0b  // Rest one turn (.)
.const CMD_SEARCH    = $0c  // Search for secrets (s)
.const CMD_OPEN      = $0d  // Open door (o)
.const CMD_CLOSE     = $0e  // Close door (c)
.const CMD_PICKUP    = $0f  // Pick up item (g or ,)
.const CMD_DROP      = $10  // Drop item (d)
.const CMD_INVENTORY = $11  // Show inventory (i)
.const CMD_EQUIPMENT = $12  // Show equipment (e)
.const CMD_WEAR      = $13  // Wear/wield (w)
.const CMD_TAKEOFF   = $14  // Take off (t)
.const CMD_EAT       = $15  // Eat (E)
.const CMD_QUAFF     = $16  // Quaff potion (q)
.const CMD_READ      = $17  // Read scroll (r)
.const CMD_AIM       = $18  // Aim wand (a)
.const CMD_USE       = $19  // Use staff (u)
.const CMD_CAST      = $1a  // Cast spell (m)
.const CMD_PRAY      = $1b  // Pray (p)
.const CMD_CHAR_INFO = $1c  // Character info (C)
.const CMD_MAP       = $1d  // Full map view (M)
.const CMD_RECALL    = $1e  // Monster recall (/)
.const CMD_LOOK      = $1f  // Look around (l or x)
.const CMD_RUN       = $20  // Run (shift+direction or R)
.const CMD_SAVE      = $21  // Save and quit (S)
.const CMD_QUIT      = $22  // Quit without saving (Q)
.const CMD_HELP      = $23  // Help (?)
.const CMD_VERSION   = $24  // Version (V)
.const CMD_RUN_N     = $25  // Run north
.const CMD_RUN_S     = $26  // Run south
.const CMD_RUN_W     = $27  // Run west
.const CMD_RUN_E     = $28  // Run east
.const CMD_RUN_NW    = $29  // Run northwest
.const CMD_RUN_NE    = $2a  // Run northeast
.const CMD_RUN_SW    = $2b  // Run southwest
.const CMD_RUN_SE    = $2c  // Run southeast
.const CMD_GAIN      = $2d  // Gain spell from book (f)
.const CMD_FIRE      = $2e  // Fire ranged weapon (SHIFT+F)
.const CMD_THROW     = $2f  // Throw item (SHIFT+T)
.const CMD_REFUEL    = $30  // Refuel lamp (SHIFT+R)
.const CMD_BASH      = $31  // Bash (SHIFT+D)
.const CMD_TUNNEL    = $32  // Tunnel (+)

// Direction offsets: dx, dy for each movement command
// Index = CMD_MOVE_x - CMD_MOVE_N
dir_dx: .byte  0,  0, -1, 1, -1, 1, -1, 1  // N S W E NW NE SW SE
dir_dy: .byte -1,  1,  0, 0, -1,-1,  1, 1
dir_opposite: .byte 1, 0, 3, 2, 7, 6, 5, 4  // N↔S, W↔E, NW↔SE, NE↔SW

// ============================================================
// Subroutines
// ============================================================

// input_get_key — Wait for a keypress, return PETSCII code
// Output: A = PETSCII code of key pressed
// Banking-safe + IRQ-safe: banks in KERNAL, enables IRQ for keyboard
// scanning, polls until key available, then restores original banking
// and interrupt state. Works from ANY context — main game (CLI/$36),
// overlays (SEI/$34), or banked code (SEI/$34).
// NOTE: Polls $C6 (keyboard buffer count) before calling GETIN.
// GETIN sets $CC=$C6 internally — calling with $C6>0 keeps $CC
// non-zero, preventing KERNAL cursor blink from corrupting color RAM.
// Preserves: X, Y
// input_run_key_held — Non-blocking: returns nonzero if any key is physically held
// Used by the pre-arm running path in game_loop.s. This must ignore KERNAL
// key-repeat semantics; buffered repeats would cancel a run after a short delay.
// Output: A = nonzero if any key held, 0 if no key
// Preserves: X, Y
input_run_key_held:
    lda $01
    pha
    php
    sei
    lda #BANK_NO_BASIC
    sta $01

    lda CIA1_PORTA
    sta irk_save_pra
    lda CIA1_DDRA
    sta irk_save_ddra
    lda CIA1_DDRB
    sta irk_save_ddrb

    lda #$ff
    sta CIA1_DDRA
    lda #$00
    sta CIA1_DDRB
    lda #$00
    sta CIA1_PORTA
    lda CIA1_PORTB
    cmp #$ff
    beq !irk_none+
    lda #1
    bne !irk_store+
!irk_none:
    lda #0
!irk_store:
    sta irk_result

    lda irk_save_pra
    sta CIA1_PORTA
    lda irk_save_ddra
    sta CIA1_DDRA
    lda irk_save_ddrb
    sta CIA1_DDRB

    plp
    pla
    sta $01
    lda irk_result
    rts

// input_run_key_check — Backward-compatible alias for held-state polling
input_run_key_check:
    jmp input_run_key_held

// input_run_cancel_check — Non-blocking run cancel poll
// Uses the same edge detector contract as C128, but samples only physical held state.
input_run_cancel_check:
    jsr input_run_key_held
    jmp input_run_process_sample

// input_run_cancel_reset — Reset run-cancel state
input_run_cancel_reset:
    lda #0
    sta irk_last_sample
    sta irk_stable
    rts

// input_run_process_sample — Debounced edge/state machine for running cancel
// Input: A = sampled held-state (0 = no key, nonzero = key held)
// Output: A = 1 on a newly-stable key-down edge, 0 otherwise
input_run_process_sample:
    beq !irps_norm_done+
    lda #1
!irps_norm_done:
    cmp irk_last_sample
    beq !irps_confirm+
    sta irk_last_sample
    lda #0
    rts

!irps_confirm:
    cmp irk_stable
    beq !irps_none+
    sta irk_stable
    beq !irps_none+
    rts
!irps_none:
    lda #0
    rts

irk_save_pra:  .byte 0
irk_save_ddra: .byte 0
irk_save_ddrb: .byte 0
irk_last_sample: .byte 0
irk_stable: .byte 0
irk_result: .byte 0

input_get_key:
    lda $01
    pha
    php                     // Save processor flags (preserves I flag)
    lda #BANK_NO_BASIC      // $36 — KERNAL + I/O, no BASIC ROM
    sta $01
    cli                     // Enable IRQ — keyboard scan needs it
!igk_poll:
    inc zp_entropy
    lda $c6                 // Keyboard buffer count (filled by IRQ handler)
    beq !igk_poll-          // No key yet, keep polling
    jsr KERNAL_GETIN        // Read key ($CC set to non-zero = blink suppressed)
    sta igk_key
    plp                     // Restore original I flag (SEI if was SEI)
    pla
    sta $01                 // Restore original banking state
    lda igk_key
    rts
igk_key: .byte 0

// input_wait_release — Drain pending buffered keys and wait until no key is pending
// Used before one-shot "press any key" prompts so a prior selection key does
// not auto-dismiss the next screen.
// Preserves: X, Y
input_wait_release:
    lda $01
    pha
    php                     // Save processor flags (preserves I flag)
    lda #BANK_NO_BASIC      // $36 — KERNAL + I/O, no BASIC ROM
    sta $01
    cli                     // Keep KERNAL keyboard IRQ scanning active

    // Drain any already-buffered keypresses.
!iwr_drain:
    inc zp_entropy
    lda KBDBUF_COUNT
    beq !iwr_wait+
    jsr KERNAL_GETIN
    jmp !iwr_drain-

    // Require two consecutive empty-buffer polls for stability.
!iwr_wait:
    inc zp_entropy
    lda KBDBUF_COUNT
    bne !iwr_drain-
    lda KBDBUF_COUNT
    bne !iwr_drain-

    plp                     // Restore original I flag
    pla
    sta $01                 // Restore original banking state
    rts

// input_get_command — Wait for a keypress, return command ID
// Output: A = command ID (CMD_* constant)
//         zp_input_cmd = same
//         zp_input_count = repeat count (currently always 1; numeric prefixes are deferred)
// Preserves: nothing
input_get_command:
    // Flush keyboard buffer to discard keys pressed during rendering
    lda #0
    sta $c6                 // KERNAL keyboard buffer count

    lda #1
    sta zp_input_count      // Default repeat count = 1
    // Numeric repeat prefixes are not implemented.
    // Keep `zp_input_count` pinned to 1 until the feature is explicitly revived.

!get_key:
    jsr input_get_key
    jsr petscii_to_command
    cmp #CMD_NONE
    beq !get_key-           // Unknown key, try again

    sta zp_input_cmd
    rts

// petscii_to_command — Convert PETSCII key code to command ID
// Input:  A = PETSCII code
// Output: A = command ID
// Preserves: X, Y
petscii_to_command:
    // Check the key mapping table
    ldx #0
!loop:
    cmp key_map_petscii,x
    beq !found+
    inx
    cpx #key_map_count
    bcc !loop-
    // Not found
    lda #CMD_NONE
    rts
!found:
    lda key_map_cmd,x
    rts

// ============================================================
// Key mapping table
// PETSCII codes → command IDs
// C64 PETSCII: uppercase letters are $41-$5A in shifted mode,
// but in unshifted mode (which we use), pressing a letter key
// produces $41-$5A regardless. KERNAL GETIN returns these codes.
// ============================================================

key_map_petscii:
    // Vi-keys (movement) — uppercase PETSCII
    .byte $4b   // K — north
    .byte $4a   // J — south
    .byte $48   // H — west
    .byte $4c   // L — east
    .byte $59   // Y — northwest
    .byte $55   // U — northeast
    .byte $42   // B — southwest
    .byte $4e   // N — southeast
    // Cursor keys (C64 PETSCII codes)
    .byte $91   // Cursor up — north
    .byte $11   // Cursor down — south
    .byte $9d   // Cursor left — west
    .byte $1d   // Cursor right — east
    // Game commands
    .byte $3e   // > — stairs down
    .byte $3c   // < — stairs up
    .byte $2e   // . — rest
    .byte $53   // S — search
    .byte $4f   // O — open
    .byte $43   // C — close
    .byte $47   // G — pick up (get)
    .byte $2c   // , — pick up (alt)
    .byte $44   // D — drop
    .byte $49   // I — inventory
    .byte $45   // E — equipment / eat
    .byte $57   // W — wear/wield
    .byte $54   // T — take off
    .byte $51   // Q — quaff
    .byte $52   // R — read scroll
    .byte $41   // A — aim wand
    .byte $5a   // Z — use staff (u is taken by NE movement)
    .byte $4d   // M — cast spell (magic)
    .byte $50   // P — pray
    .byte $3f   // ? — help
    // Special
    .byte $58   // X — look / examine
    .byte $46   // F — gain spell from book
    // Shifted keys (C64 unshifted mode: SHIFT+letter = PETSCII $C1-$DA)
    .byte $c3   // SHIFT+C — character info
    .byte $d1   // SHIFT+Q — quit
    .byte $c5   // SHIFT+E — eat
    .byte $d3   // SHIFT+S — save and quit
    .byte $c6   // SHIFT+F — fire ranged weapon
    .byte $d4   // SHIFT+T — throw item
    .byte $d2   // SHIFT+R — refuel lamp
    .byte $c4   // SHIFT+D — bash
    .byte $2b   // + — tunnel
    .byte $2f   // / — monster recall
    // Shifted vi-keys (running)
    .byte $cb   // SHIFT+K — run north
    .byte $ca   // SHIFT+J — run south
    .byte $c8   // SHIFT+H — run west
    .byte $cc   // SHIFT+L — run east
    .byte $d9   // SHIFT+Y — run northwest
    .byte $d5   // SHIFT+U — run northeast
    .byte $c2   // SHIFT+B — run southwest
    .byte $ce   // SHIFT+N — run southeast

key_map_cmd:
    // Movement
    .byte CMD_MOVE_N
    .byte CMD_MOVE_S
    .byte CMD_MOVE_W
    .byte CMD_MOVE_E
    .byte CMD_MOVE_NW
    .byte CMD_MOVE_NE
    .byte CMD_MOVE_SW
    .byte CMD_MOVE_SE
    // Cursor keys
    .byte CMD_MOVE_N
    .byte CMD_MOVE_S
    .byte CMD_MOVE_W
    .byte CMD_MOVE_E
    // Game commands
    .byte CMD_STAIRS_DN
    .byte CMD_STAIRS_UP
    .byte CMD_REST
    .byte CMD_SEARCH
    .byte CMD_OPEN
    .byte CMD_CLOSE
    .byte CMD_PICKUP
    .byte CMD_PICKUP
    .byte CMD_DROP
    .byte CMD_INVENTORY
    .byte CMD_EQUIPMENT
    .byte CMD_WEAR
    .byte CMD_TAKEOFF
    .byte CMD_QUAFF
    .byte CMD_READ
    .byte CMD_AIM
    .byte CMD_USE
    .byte CMD_CAST
    .byte CMD_PRAY
    .byte CMD_HELP
    // Special
    .byte CMD_LOOK
    .byte CMD_GAIN
    // Shifted keys
    .byte CMD_CHAR_INFO
    .byte CMD_QUIT
    .byte CMD_EAT
    .byte CMD_SAVE
    .byte CMD_FIRE
    .byte CMD_THROW
    .byte CMD_REFUEL
    .byte CMD_BASH
    .byte CMD_TUNNEL
    .byte CMD_RECALL
    // Shifted vi-keys (running)
    .byte CMD_RUN_N
    .byte CMD_RUN_S
    .byte CMD_RUN_W
    .byte CMD_RUN_E
    .byte CMD_RUN_NW
    .byte CMD_RUN_NE
    .byte CMD_RUN_SW
    .byte CMD_RUN_SE

key_map_end:
.label key_map_count = key_map_cmd - key_map_petscii
.assert "Key map tables same size", key_map_count, key_map_end - key_map_cmd
