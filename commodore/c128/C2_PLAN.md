# C2 — C128 Keyboard Matrix and Extended Key Support

The C128 keyboard contains 24 additional keys not found on the C64, including a full numeric keypad and dedicated function keys (HELP, ALT, ESC). These are essential for a professional roguelike experience (numpad movement).

## Root Cause Analysis

1.  **Incomplete Scan Loop**: `input128.s` currently only iterates through Rows 0–7 via `$DC00`.
2.  **I/O Port Neglect**: Extended lines 8 and 9 are controlled by the 8502 Processor Port at `$D02F`. Bit 6 drives Line 8; Bit 7 drives Line 9.
3.  **Matrix Mapping**: The scan code table currently ends at 63. It must be expanded to 80+ to accommodate the new keys.

## Proposed Fixes

### 1. Expand `cia_scan_petscii` to 10 Rows
Modify the scanning loop to handle the transition from CIA1 to the 8502 I/O port.

- **Rows 0–7**: Drive `$DC00`, read `$DC01`. (Ensure `$D02F` bits 6/7 are high).
- **Row 8 (Line 8)**: Set `$DC00 = $FF`, set `$D02F` bit 6 = 0, read `$DC01`.
- **Row 9 (Line 9)**: Set `$DC00 = $FF`, set `$D02F` bit 7 = 0, read `$DC01`.

### 2. Update `cia_scancode_table`
Expand the table to include the following mappings (Sense bits 0–7):

**Row 8 (Line 8 - $D02F bit 6):**
- 0: ALT
- 1: KP 8 (Up)
- 2: KP 5 (Wait)
- 3: KP 2 (Down)
- 4: KP 4 (Left)
- 5: KP 7 (Home/NW)
- 6: KP 1 (End/SW)
- 7: KP 0 (Ins)

**Row 9 (Line 9 - $D02F bit 7):**
- 0: ESC
- 1: KP +
- 2: KP -
- 3: LINE FEED
- 4: KP 9 (PgUp/NE)
- 5: KP 6 (Right)
- 6: KP 3 (PgDn/SE)
- 7: KP . (Del)

### 3. Implement Numpad Movement Mapping
Update `petscii_to_command` to map these new PETSCII codes to the existing `CMD_MOVE_*` constants. This allows the player to use the numeric keypad for 8-way movement and the '5' key for resting, which is the standard roguelike configuration.

### 4. Handle "No-Scroll" and "40/80" (Optional/Row 10)
Row 10 (Bit 7 of `$D02F` on some revisions, or a separate sense) contains the 40/80 column switch. While not needed for commands, detecting this allows the game to potentially switch rendering backends dynamically (though current plan is to stick to 80-col).

## Success Criteria

- The numeric keypad (1–9) correctly moves the player in all 8 directions.
- The '5' key on the keypad triggers a "rest" command (`CMD_REST`).
- The ESC key correctly dismisses menus/prompts (mapped to `CMD_QUIT` or `CMD_BACK`).
- No "ghosting" occurs (pressing '8' on the keypad does not trigger the 'W' key on the main keyboard).
