# Cross-Platform UI & Quality-of-Life Enhancements Design (Backlog)

This document preserves five UI and QoL features that were built opportunistically in the CP/M 2.2 Z80 M2–M5 overlays before full parity review. They were reverted from CP/M Z80 so all 8 active ports (`C64`, `C128`, `Plus/4`, `Apple IIe`, `Commander X16`, `Atari 8-bit`, `BBC Master 128`, and `CP/M 2.2 Z80`) share identical 6502/VMS UI behavior first, and are packaged here with their Z80 reference implementations so they can be designed and shipped uniformly across all 8 ports later.

---

## Feature Summary & Parity Impact

| # | Feature | Origin in CP/M Z80 | Why Reverted for Baseline Parity | Cross-Platform Impact |
| --- | --- | --- | --- | --- |
| 1 | **Race Selection Bonus Reference Table** | `platforms/z80/cpm/ovl_start.asm` | 6502 `core/6502/player_create.s` lists only `a) Human` .. `h) Half-Troll` without stat/HD/XP%/Infra columns | **Pure UI** (`StartupOverlay`); 40-col ports need abbreviated layout or focus preview |
| 2 | **Age / Height / Weight Rolling & Expanded Character Sheet** | `ovl_start.asm` + `ovl_ui.asm` | 6502 leaves `PL_AGE`/`PL_HEIGHT`/`PL_WEIGHT` = `0`, shows compact sheet without Base stats, Title, Blows/ToHit/ToDam, or active Status Flags; **rolling non-zero `PL_WEIGHT` raises `player_weight_limit` (`inv_add.s:90` / `player_core.asm:241`)** | **Affects `player_weight_limit`** if `PL_WEIGHT != 0` (`inv_add.s` adds `PL_WEIGHT`); sheet layout differs 40 vs 80 cols |
| 3 | **Inventory, Equipment, & Home Weight/Burden Displays** | `ovl_ui.asm` + `ovl_home.asm` | 6502 `ui_inventory.s`, `ui_equipment.s`, and `ui_home.s` do not print per-item weights (`lb`) or total `Burden:` / `Wt:` (`playtest/moria_playtest/brain.py` already handles optional `lb` tails) | **Pure UI** (`UiOverlay` / `HomeOverlay`); 40-col screens lack horizontal room for right-aligned weights |
| 4 | **`Ctrl+P` Message History Viewer** | `core/z80/messages.asm` + `game_loop.asm` | All 8 ports already record `msg_history` (`8 × SCREEN_COLS`), but only CP/M Z80 exposed a `Ctrl+P` viewer modal | **Pure UI** (`HelpOverlay` / `UiOverlay` vs resident `core/6502/ui_messages.s` — must handle `MSG_HISTORY_IN_AUX`) |
| 5 | **Help Page 2 Map Terrain & Symbol Legend** | `platforms/z80/cpm/ovl_help.asm` | 6502 `ui_help_data.s` / `ui_help_data_80.s` / `ui_help_page2_data.s` use a 2-page Command Reference (`Commands` + `Keypad/Letters/Prompts`); CP/M placed all commands on Page 1 and used Page 2 for a Terrain/Item/Creature legend | **Pure UI** (`HelpOverlay`); adding as Page 3/3 keeps Page 1–2 commands intact on 40-col ports |

---

## 1. Race Selection Bonus Reference Table

### User-Facing Behavior
During character creation (`Choose your race`), display each race's six stat modifiers (`ST IN WI DX CO CH`), Hit Die (`HD`), Experience Penalty (`XP%`), and Infravision (`Infra`, `race_infra * 10 ft` or `-`) alongside `a) Human` .. `h) Half-Troll`.

### Z80 Reference Implementation (captured from `platforms/z80/cpm/ovl_start.asm`)
```z80
    ; Header line at (row 1, col 22):
ovl_start_str_race_hdr:     DB "ST IN WI DX CO CH  HD XP%  Infra", 0

    ; Inside ovl_start_select_race loop (cols 22..53 on rows 2..9):
    CALL ovl_start_format_race_info
    LD   A, D
    ADD  A, 2
    LD   B, A
    LD   C, 22
    LD   E, COL_LGREY
    LD   HL, line_buf
    CALL ovl_start_put_str

; Format race stat adjustments + HD + XP% + Infra into line_buf for race D
ovl_start_format_race_info:
    PUSH DE
    LD   A, D
    ADD  A, A
    LD   B, A
    ADD  A, A
    ADD  A, B                   ; race * 6
    LD   E, A
    LD   D, 0
    LD   IX, ovl_start_race_stat_adj
    ADD  IX, DE
    LD   DE, line_buf
    LD   B, STAT_COUNT
.mod_lp:
    LD   A, (IX + 0)
    INC  IX
    CALL ovl_start_fmt_signed3
    LD   A, ' '
    LD   (DE), A
    INC  DE
    DJNZ .mod_lp

    LD   A, ' '
    LD   (DE), A
    INC  DE

    ; Recover caller D (= race) from stack without discarding it
    POP  HL                     ; H = caller D (race)
    PUSH HL
    LD   A, H
    LD   H, 0
    LD   L, A
    LD   A, 10
    PUSH DE                     ; mul_hl_a clobbers DE (line_buf cursor)
    CALL mul_hl_a               ; HL = race * 10
    POP  DE
    LD   BC, ovl_start_race_props
    ADD  HL, BC
    PUSH HL                     ; save &race_props[race]

    ; HD (offset 0, 2 chars)
    LD   A, (HL)
    CALL ovl_start_fmt_u8_pad2
    LD   A, ' '
    LD   (DE), A
    INC  DE

    ; XP% (offset 2, 3 digits)
    POP  HL
    PUSH HL
    INC  HL
    INC  HL
    LD   A, (HL)
    CALL fmt_u8_dec
    LD   A, '%'
    LD   (DE), A
    INC  DE
    LD   A, ' '
    LD   (DE), A
    INC  DE

    ; Infra * 10 ft (offset 1)
    POP  HL
    INC  HL
    LD   A, (HL)
    OR   A
    JR   Z, .no_inf
    LD   L, A
    LD   H, 0
    LD   A, 10
    PUSH DE                     ; mul_hl_a clobbers DE (line_buf cursor)
    CALL mul_hl_a
    POP  DE
    CALL fmt_u16_dec
    LD   A, 'f'
    LD   (DE), A
    INC  DE
    LD   A, 't'
    LD   (DE), A
    INC  DE
    JR   .inf_done
.no_inf:
    LD   A, '-'
    LD   (DE), A
    INC  DE
.inf_done:
    XOR  A
    LD   (DE), A
    POP  DE
    RET
```

### Cross-Platform Considerations
- **80-col ports (`C128`, `Apple IIe`, `CX16`, `BBC Master`, `CPM`)**: Fits natively at cols 22–53 beside the 32-char left column.
- **40-col ports (`C64`, `Plus/4`, `Atari 8-bit`)**: Columns `a) Half-Troll` reach col 16, leaving only 23 cols (`17..39`) — cannot fit `ST IN WI DX CO CH HD XP% Infra` horizontally without either abbreviating to a cursor-selected bottom detail box (`rows 14–18`, updating as the user highlights a race or presses a key/info toggle) or keeping two compact rows per race.
- **Overlay Budget**: Runs inside `StartupOverlay` (`core/6502/player_create.s` + `core/6502/race_data.s`, where `race_stat_adj`, `race_hd`, `race_xp`, `race_infra` already exist!). Check `$E000-$EFFF` free slack on C64/Plus4/C128/Atari8 (`StartupOverlay` is currently near ~3.6–4.0 KB).

---

## 2. Age / Height / Weight Generation & Expanded Character Sheet

### User-Facing Behavior
1. During character generation (`ovl_start_bake_and_vitals`), roll `PL_AGE` and assign base `PL_HEIGHT` / `PL_WEIGHT` per race.
2. Expand the Character Sheet (`'C'` and post-chargen summary) to a full-screen 80-col layout showing:
   - `Sex`, `Title` (class × 8 tier from `PL_LEVEL`), `Age`, `Height`, `Weight`, `SC`, `Level`, `Exp`, `Max Dlvl`, `Gold`, `Burden` (`current / limit lb`)
   - Both `Curr` and `Base` columns for `STR..CHR`
   - `HP`, `MP`, `AC`, `Blows` (`/rnd`), `ToHit`, `ToDam`, `Hunger`, `Depth`, active status `Flags` (`Poison`, `Blind`, `Confuse`, `Paralyze`, `Afraid`, `Speed`, `Protect`, `Bless`, `Hero`, `Invis`, `Infra`, `Resist`, `ResCold`, `SeeInv`, `Invuln`, `Search`, `Rest`), and the 4×40 `Character Background`.

### Gameplay Parity Warning (`PL_WEIGHT` -> `player_weight_limit`)
- `core/6502/inv_add.s:90` (`adc player_data + PL_WEIGHT`) and `core/z80/player_core.asm:241` (`LD A, (player_data + PL_WEIGHT)`) **both already add `PL_WEIGHT` to `PL_STR_CUR * 130` (tenths of a lb) in `player_weight_limit`**!
- Currently all 6502 ports initialize `PL_AGE = PL_HEIGHT = PL_WEIGHT = 0` (`core/6502/player.s:78-80` notes `"aesthetic"`), so rolling `PL_WEIGHT` (`60..250`, i.e., `6.0..25.0 lb` extra capacity, capped at `PLAYER_WEIGHT_CAP = 3000` tenths = `300.0 lb`) changes actual gameplay encumberance capacity and save snapshots.
- **Decision required before implementation:** either roll `PL_WEIGHT` identically across all 8 ports (updating playtest expectations in `playtest/moria_playtest/abi.py` / `brain.py` / `docs/FEATURE_MAP.md` §2.1) or display `PL_WEIGHT` aesthetically while keeping `player_weight_limit` formula unchanged.

### Z80 Reference Implementation (captured from `ovl_start.asm` & `ovl_ui.asm`)
```z80
    ; From ovl_start.asm::ovl_start_bake_and_vitals:
    LD   A, (player_data + PL_RACE)
    LD   C, A
    LD   B, 0
    LD   HL, ovl_start_race_age_var
    ADD  HL, BC
    LD   A, (HL)
    CALL rng_range
    INC  A
    LD   HL, ovl_start_race_age_base
    ADD  HL, BC
    ADD  A, (HL)
    LD   (player_data + PL_AGE), A
    LD   HL, ovl_start_race_height
    ADD  HL, BC
    LD   A, (HL)
    LD   (player_data + PL_HEIGHT), A
    LD   HL, ovl_start_race_weight
    ADD  HL, BC
    LD   A, (HL)
    LD   (player_data + PL_WEIGHT), A

ovl_start_race_age_base: DB  14, 24, 75, 21, 50, 35, 11, 20
ovl_start_race_age_var:  DB   6, 16, 75, 12, 40, 15,  4, 10
ovl_start_race_height:   DB  72, 66, 60, 36, 42, 48, 66, 96
ovl_start_race_weight:   DB 180,130,100, 60, 90,150,150,250
```
See `ovl_ui.asm` (`ovl_ui_character`, `ovl_ui_draw_status_flags`, `ovl_ui_char_labels`, `ovl_ui_char_fields`, `ovl_ui_flag_table`) preserved in git history (`platforms/z80/cpm/ovl_ui.asm` prior to the parity revert) for the 3-column 80×24 label layout and 17-entry status flag word wrapper.

### Cross-Platform Considerations
- **40-col ports**: Cannot fit 3 columns on rows 2–6; either paginate the character sheet (`Page 1`: identity/vitals/stats, `Page 2`: combat/flags/background — matching VMS Moria's `character` view toggle) or keep compact 2-col layout (`ToHit`/`ToDam`/`Blows` + `Flags` on rows 11–12).
- **80-col ports**: Fits cleanly on rows 0–20 with `hall_layout_character_*`.
- **Overlay Budget**: Notice C64/C128 `UiOverlay` (`4,096 B`) is near capacity; `ovl_ui_titles` (48 class titles) + flag strings require BPE/Huffman compression or moving titles/strings to cold data.

---

## 3. Inventory, Equipment, & Home Weight/Burden Displays

### User-Facing Behavior
- **Inventory (`i`) & Equipment (`e`)**: Print `Burden: XXX.X/YYY.Y lb` on Row 0 beside the `Inventory` / `Equipment` title, and print right-aligned per-slot total weight `NNN.N lb` (accounting for quantity and `EGO_GREAT_MASS` 2× weight) at col 69 for each non-empty slot.
- **Home (`8`)**: Print `Wt: XXX.X/YYY.Y lb` on Row 19 (`col 44`) beside the menu and `Gold: N`.

### Z80 Reference Implementation (captured from `ovl_ui.asm` & `ovl_home.asm`)
```z80
    ; From ovl_ui.asm:
ovl_ui_draw_hdr_burden:
    PUSH HL
    CALL inv_calc_weight
    CALL screen_hard_clear
    POP  HL
    LD   B, 0
    LD   C, 2
    CALL ovl_ui_put_cstr_w
    LD   B, 0
    LD   C, 42
    LD   E, COL_LGREY
    LD   HL, ovl_ui_str_burden_hdr      ; "Burden:"
    CALL ovl_ui_put_cstr
    CALL ovl_ui_fmt_burden_buf
    LD   B, 0
    LD   C, 50
    JP   ovl_ui_put_linebuf_w

; Print item description at (B, D) clamped to E chars, and weight at (B, 69).
; Input: B=row, C=inv_slot (0..33), D=desc_col, E=max_len.
ovl_ui_draw_slot_desc_wt:
    PUSH BC
    PUSH DE
    LD   A, C
    LD   DE, line_buf
    CALL item_format_inv_slot
    POP  DE
    LD   L, E
    LD   H, 0
    LD   BC, line_buf
    ADD  HL, BC
    LD   (HL), 0
    POP  BC
    PUSH BC
    PUSH DE
    LD   A, C
    CALL ovl_ui_inv_color_a
    POP  HL
    LD   C, H
    LD   HL, line_buf
    CALL screen_put_str
    POP  BC
    PUSH BC
    LD   A, C
    CALL ovl_ui_fmt_slot_wt_buf
    POP  BC
    LD   C, 69
    LD   E, COL_LGREY
    JP   ovl_ui_put_linebuf

ovl_ui_fmt_slot_wt_buf:
    LD   C, A
    LD   B, 0
    LD   HL, inv_ego
    ADD  HL, BC
    LD   A, (HL)
    LD   D, A
    AND  ITEM_PAGE_BIT
    LD   (item_cur_page), A
    LD   HL, inv_item_id
    ADD  HL, BC
    LD   A, (HL)
    CALL icat_select_id
    JR   C, .wt_zero
    CALL icat_get_weight
    JR   C, .wt_zero
    LD   A, D
    AND  EGO_ID_MASK
    CP   EGO_GREAT_MASS
    JR   NZ, .no_dbl
    ADD  HL, HL
.no_dbl:
    LD   DE, inv_qty
    EX   DE, HL
    ADD  HL, BC
    LD   A, (HL)
    CALL mul_de_a
    JR   .fmt
.wt_zero:
    LD   HL, 0
.fmt:
    LD   DE, line_buf
    CALL ovl_ui_fmt_wt_tenths
    LD   HL, ovl_ui_str_lb
    JP   ovl_ui_append_str

    ; From ovl_home.asm row 19:
    ; Weight display on row 19 col 44: "Wt: XXX.X/YYY.Y lb"
    LD   B, STORE_MENU_ROW
    LD   C, 44
    LD   E, COL_CYAN
    LD   HL, ovl_home_str_wt            ; "Wt: "
    CALL screen_put_str
    LD   DE, line_buf
    LD   HL, (inven_weight_lo)
    CALL ovl_home_fmt_wt_tenths
    LD   A, '/'
    LD   (DE), A
    INC  DE
    PUSH DE
    CALL player_weight_limit
    POP  DE
    CALL ovl_home_fmt_wt_tenths
    LD   HL, ovl_home_str_lb            ; " lb", 0
    LD   BC, 4
    LDIR
    LD   B, STORE_MENU_ROW
    LD   C, 48
    LD   E, COL_LGREY
    LD   HL, line_buf
    CALL screen_put_str
```

### Cross-Platform Considerations
- **Playtest Compatibility**: `playtest/moria_playtest/brain.py` already handles optional `NNN.N lb` suffixes (`CPM_WEIGHT_TAIL`).
- **40-col vs 80-col**:
  - Total `Burden: XXX.X/YYY.Y lb` fits easily in Row 0 on 80-col ports and in Row 1 (`col 20+`) or Row 19 on 40-col ports.
  - Per-item `NNN.N lb` fits natively at col 69 on 80-col ports (`Inventory` / `Equipment` / `?` prompts); on 40-col ports, item descriptions already fill cols `4..39`, so either show per-item weights only on 80-col ports (like `ui_equipment_wrap.s` handles 40-col wrapping) or omit per-item column on 40-col while showing total `Burden: X/Y lb` on all 8 ports.

---

## 4. `Ctrl+P` Message History Viewer

### User-Facing Behavior
Pressing `Ctrl+P` (`$10`) in gameplay opens a non-turn-consuming modal listing the last `<= 8` recorded messages chronologically (`msg_history` ring buffer, oldest to newest) with `[Press any key to continue]`, then redraws the dungeon screen cleanly.

### Z80 Reference Implementation (captured from `core/z80/messages.asm` & `game_loop.asm`)
```z80
    ; In game_loop.asm _gl_ui_tbl:
    DB   KEY_CTRL_P : DW msg_show_history

; msg_show_history — Display last <= 8 messages chronologically and await key.
; Sets UI redraw flags on exit so caller cleanly restores game view.
msg_show_history:
    CALL screen_clear
    LD   B, 0
    LD   C, 1
    LD   E, COL_WHITE
    LD   HL, _msg_hdr_str               ; "Message History (last 8):"
    CALL screen_put_str

    LD   A, (msg_hist_count_used)
    OR   A
    JR   NZ, .has_msgs
    LD   B, 2
    LD   C, 2
    LD   E, COL_GREY
    LD   HL, _msg_none_str              ; "(no messages yet)"
    CALL screen_put_str
    JR   .footer

.has_msgs:
    LD   B, A                           ; B = total count (1..8)
    ; Oldest slot = (msg_hist_idx - count_used) & 7
    LD   A, (msg_hist_idx)
    SUB  B
    AND  MSG_HIST_COUNT - 1
    LD   C, A                           ; C = current slot index
    LD   D, 2                           ; D = screen row (2..9)
.disp_loop:
    PUSH BC
    PUSH DE
    LD   E, C
    CALL _msg_slot_ptr_de               ; DE = string ptr
    EX   DE, HL
    POP  DE                             ; D = row
    PUSH DE
    LD   B, D
    LD   C, 2
    LD   E, COL_MSG_TEXT
    CALL screen_put_str
    POP  DE
    POP  BC
    INC  D
    LD   A, C
    INC  A
    AND  MSG_HIST_COUNT - 1
    LD   C, A
    DJNZ .disp_loop

.footer:
    LD   B, 11
    LD   C, 1
    LD   E, COL_PROMPT
    LD   HL, _msg_ftr_str               ; "[Press any key to continue]"
    CALL screen_put_str
    CALL screen_flush
    CALL input_wait_any_key
    CALL screen_clear
    LD   A, 1
    LD   (hal_layout_visibility_force_redraw), A
    LD   A, (zp_ui_dirty)
    OR   UI_DIRTY_FORCE | UI_DIRTY_STATUS | UI_DIRTY_MAP
    LD   (zp_ui_dirty), A
    RET
```

### Cross-Platform Considerations
- **Data Already Present Everywhere**: All 7 6502 ports already write every message into `msg_history` (`8 × SCREEN_COLS` bytes, `core/6502/ui_messages.s:30-38`). Note `core/6502/ui_messages.s` fills unused `msg_history` slots with `$20` (spaces) and tracks `msg_hist_idx` (needs a `msg_hist_count` or non-blank check to skip empty slots cleanly).
- **Banking / Aux RAM**: On `C128`, `Apple IIe`, `CX16`, and `BBC Master`, `MSG_HISTORY_IN_AUX = 1` keeps `msg_history` in Bank 1 / Aux / HiRAM / Shadow RAM (`mmu_safe_map_read*` / Aux copy helper required to display lines).
- **Zero Resident Cost Option**: Dispatch `Ctrl+P` (`$10`) via a trampoline into `UiOverlay` (or `HelpOverlay`) instead of resident `ui_messages.s`, since `MORIA8.COM` and C64/Atari8 resident banks are tight (`< 100 B`).

---

## 5. Help Map Terrain & Item/Creature Symbol Legend Page

### User-Facing Behavior
Include a dedicated Help page showing all map terrain glyphs (`@`, `.`, `#`, `%`, `:`, `+`, `'`, `<`, `>`, `^`, `1-8`) and item/creature categories (`$ / &`, `! / ?`, `= / "`, `- / _`, `/ / |`, `\ / ,`, `* / ~`, `( / [`, `] / )`, `{ / }`, `a-z/A-Z`).

### Z80 Reference Implementation (captured from `platforms/z80/cpm/ovl_help.asm`)
```z80
ovl_help_hdr_p2: DB " Map Legend & Notes (Page 2/2) ", 0

ovl_help_page2_data:
    DB HELP_TOK_NL
    DB HELP_TOK_CYAN, "MAP TERRAIN LEGEND", HELP_TOK_TAB2, "ITEMS & CREATURES", HELP_TOK_NL
    DB HELP_TOK_KEY, "@   ", HELP_TOK_DESC, "Player (You)", HELP_TOK_TAB2, HELP_TOK_KEY, "$ / &  ", HELP_TOK_DESC, "Gold/Gems / Chest", HELP_TOK_NL
    DB HELP_TOK_KEY, ".   ", HELP_TOK_DESC, "Open floor", HELP_TOK_TAB2, HELP_TOK_KEY, "! / ?  ", HELP_TOK_DESC, "Potion / Scroll", HELP_TOK_NL
    DB HELP_TOK_KEY, "#   ", HELP_TOK_DESC, "Stone wall / secret door", HELP_TOK_TAB2, HELP_TOK_KEY, "= / ", 0x22, "  ", HELP_TOK_DESC, "Ring / Amulet", HELP_TOK_NL
    DB HELP_TOK_KEY, "%   ", HELP_TOK_DESC, "Magma or Quartz vein", HELP_TOK_TAB2, HELP_TOK_KEY, "- / _  ", HELP_TOK_DESC, "Wand / Staff", HELP_TOK_NL
    DB HELP_TOK_KEY, ":   ", HELP_TOK_DESC, "Pile of rubble", HELP_TOK_TAB2, HELP_TOK_KEY, "/ / |  ", HELP_TOK_DESC, "Polearm / Sword", HELP_TOK_NL
    DB HELP_TOK_KEY, "+   ", HELP_TOK_DESC, "Closed / locked door", HELP_TOK_TAB2, HELP_TOK_KEY, 0x5C, " / ,  ", HELP_TOK_DESC, "Digging tool / Food", HELP_TOK_NL
    DB HELP_TOK_KEY, 0x27, "   ", HELP_TOK_DESC, "Open / broken door", HELP_TOK_TAB2, HELP_TOK_KEY, "* / ~  ", HELP_TOK_DESC, "Light / Misc item", HELP_TOK_NL
    DB HELP_TOK_KEY, "<   ", HELP_TOK_DESC, "Staircase up", HELP_TOK_TAB2, HELP_TOK_KEY, "( / [  ", HELP_TOK_DESC, "Soft / Hard armor", HELP_TOK_NL
    DB HELP_TOK_KEY, ">   ", HELP_TOK_DESC, "Staircase down", HELP_TOK_TAB2, HELP_TOK_KEY, "] / )  ", HELP_TOK_DESC, "Helm/Glove/Boot / Shield", HELP_TOK_NL
    DB HELP_TOK_KEY, "^   ", HELP_TOK_DESC, "Trap or Rune of Protection", HELP_TOK_TAB2, HELP_TOK_KEY, "{ / }  ", HELP_TOK_DESC, "Ammo / Bow, Crossbow", HELP_TOK_NL
    DB HELP_TOK_KEY, "1-8 ", HELP_TOK_DESC, "Town shops (7=BM, 8=Home)", HELP_TOK_TAB2, HELP_TOK_KEY, "a-z/A-Z", HELP_TOK_DESC, "Monsters (/ identifies)", HELP_TOK_NL
    DB HELP_TOK_NL
    DB HELP_TOK_CYAN, "KEYPAD & VI COMPASS", HELP_TOK_TAB2, "PROMPT CONTROLS", HELP_TOK_NL
    DB HELP_TOK_DESC, "  7 8 9      y k u", HELP_TOK_TAB2, HELP_TOK_KEY, "ESC / Q     ", HELP_TOK_DESC, "Cancel / Return", HELP_TOK_NL
    DB HELP_TOK_DESC, "  4 5 6      h . l   (5=Rest)", HELP_TOK_TAB2, HELP_TOK_KEY, "SPACE / CR  ", HELP_TOK_DESC, "Next page / Accept", HELP_TOK_NL
    DB HELP_TOK_DESC, "  1 2 3      b j n", HELP_TOK_TAB2, HELP_TOK_KEY, "L (in Help) ", HELP_TOK_DESC, "License & Source Offer", HELP_TOK_NL
    DB HELP_TOK_END
```

### Cross-Platform Considerations
- **Keep Existing 2-Page Command Reference Intact**: Add the Map & Symbol Legend as **Page 3/3** across both 40-col (`ui_help_data.s` + `ui_help_page2_data.s`) and 80-col (`ui_help_data_80.s` + CP/M `ovl_help.asm`), splitting Terrain (rows 1–12) and Items/Creatures (rows 13–22) into a single column on 40-col ports and keeping 2 columns on 80-col ports.
- **Glyph Variations**: Check per-port glyphs where they diverge (e.g. solid block `#` / trap symbol `·` on PETSCII vs `#` / `^` on ASCII/CP/M; Apple IIe `a2_map_char` ASCII equivalents).
