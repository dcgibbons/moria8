# Test Plan: Top 5 Untested Routines

This document outlines the exact technical approach for wrapping the 5 largest untested routines in the Moria C64/C128 codebase with headless VICE unit tests.

These 5 routines account for ~2,100 lines of previously unverified assembly.

---

## 1. `main_loop` (`common/game_loop.s` & `c64/main.s`)
**Problem:** `main_loop` is the core dispatch loop. It blocks on keyboard input, processes time, and acts on player intentions. It's difficult to test because it relies heavily on endless loops and blocking KERNAL GETIN calls.
**Testing Strategy (Mocked Input Dispatch):**
1. **Create `test_main_loop.s`** in `c64/tests/`.
2. **Mocking `get_input`:** Override or intercept the standard input fetch subroutine so it returns a predefined sequence of keys (e.g., `[KEY_UP, KEY_WAIT, 's', 'q']`) instead of blocking.
3. **State Setup:**
   - Initialize a mini 3x3 map in `map_row_lo/hi`.
   - Set `zp_player_x`/`y` to center.
   - Set `zp_player_hp` to max.
4. **Execution:** Jump into `main_loop`. If `get_input` is mocked to yield a "quit" or "suicide" key (`Q` or `^K`), the loop will eventually exit gracefully.
5. **Assertions:**
   - `<assert_eq zp_player_y, expected_y>` (Did KEY_UP move the player?)
   - `<assert_eq zp_turn_count, expected_turns>` (Did time pass correctly?)
6. **C128 Variant:** Duplicate for `c128/tests/test_main_loop128.s` using the banked memory setup.

---

## 2. `render_viewport` (`c64/dungeon_render.s` / `c128/dungeon_render_vdc.s`)
**Problem:** Rendering tests require asserting against screen RAM / VDC memory, not just Zero Page state.
**Testing Strategy (Screen Memory Verification):**
1. **Create `test_dungeon_render.s`** (or append to existing `test_dungeon.s` / `test_vdc_attr128.s`).
2. **State Setup:**
   - Pre-fill `map_row_lo/hi` arrays with a known pattern: walls, floors, a known monster at a specific coordinate, and a known item.
   - Set `zp_player_x = 10`, `zp_player_y = 10`.
3. **Execution:** Call `render_viewport`.
4. **Assertions (C64):**
   - Check specific offsets in `$0400` (Screen RAM) and `$D800` (Color RAM). For example, character at $0400 + (row * 40) + col should equal `TILE_WALL_CHAR`.
5. **Assertions (C128):**
   - Use `vdc_read` to fetch specific bytes from VDC display RAM and attribute RAM. Assert character and color (like `COL_LGREY`).

---

## 3. `status_draw` (`common/ui_status.s`)
**Problem:** Renders the bottom two rows of the screen (stats, HP, level, AC). Needs binary-to-decimal (BCD) output verification.
**Testing Strategy (UI Text Output Parsing):**
1. **Create `test_ui_status.s`**.
2. **State Setup:**
   - Set `zp_player_hp = 12`, `zp_player_max_hp = 15`.
   - Set `zp_player_str = 18`.
   - Set `zp_player_gold_lo/hi = 100`.
3. **Execution:** Call `status_draw`.
4. **Assertions:**
   - Read from the screen RAM addresses assigned to the status bar (e.g., `$0798` on C64, or VDC row 23/24 on C128).
   - Assert that the exact PETSCII string `"12/15"` appears at the expected offset for HP.
   - Assert that `"18"` appears for STR.

---

## 4. `render_single_tile` (`c64/dungeon_render.s` / `c128/dungeon_render_vdc.s`)
**Problem:** Need to verify the strict priority order of rendering: Player > Monster > Object > Feature > Map tile.
**Testing Strategy (Priority Assertions):**
1. **Create `test_render_tile.s`**.
2. **State Setup:**
   - Configure a single map coordinate `X=5, Y=5` with a floor tile `TILE_FLOOR`.
3. **Test Cases:**
   - **Case 1 (Feature):** Add `FLAG_SECRET_DOOR`. Call `render_single_tile`. Assert screen RAM shows a wall character.
   - **Case 2 (Object):** Put a potion in `object_table` at `X=5, Y=5`. Call `render_single_tile`. Assert screen RAM shows `!` character.
   - **Case 3 (Monster):** Put an Orc in `monster_table` at `X=5, Y=5`. Call `render_single_tile`. Assert screen RAM shows `o` character, overriding the potion.
   - **Case 4 (Player):** Set `zp_player_x = 5`, `zp_player_y = 5`. Call `render_single_tile`. Assert screen RAM shows `@` character, overriding the Orc.

---

## 5. `ui_char_display` (`common/ui_character.s`)
**Problem:** Renders a full-screen overlay panel showing player stats, history, and equipment.
**Testing Strategy (Overlay Generation & Dismissal):**
1. **Create `test_ui_character.s`**.
2. **State Setup:**
   - Give the player a specific weapon in equipment slot 0 (e.g., "Long Sword").
   - Give the player a specific class/race.
3. **Execution:**
   - Mock `get_input` to return `KEY_SPACE` so the overlay dismisses immediately after drawing.
   - Call `ui_char_display`.
   - *Alternative for pure render test:* Call the internal `char_draw_screen` routine directly if available, bypassing the blocking input loop.
4. **Assertions:**
   - Verify specific substrings the screen/VDC.
   - For example, verify `"LONG SWORD"` is written at the `EQUIP_ROW` offset.
   - For C128, ensure that banked string fetches (for race/class names) mapped correctly to VDC ram.
