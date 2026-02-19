# Moria C64/C128 — Build Plan

> Active development plans and tracking for the Moria C64/C128 port.
> See [DESIGN.md](DESIGN.md) for architecture reference, [BUILDPLAN_HISTORY.md](BUILDPLAN_HISTORY.md) for completed work.

---

## Current State (2026-02-16)

**All core phases complete.** The game is fully playable from title screen through dungeon exploration, combat, magic, stores, save/load, death, and high scores. Ranged combat (R1.1) added. OPT-1 code size optimizations applied (excluding OPT-1.1).

### Phase Completion Summary

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | Skeleton and Infrastructure | ✅ Complete |
| 2 | Player and Character Creation | ✅ Complete |
| 3 | The Town Level | ✅ Complete |
| 4 | Dungeon Generation and Navigation | ✅ Complete |
| 5 | Monsters | ✅ Complete |
| 6 | Items and Inventory | ✅ Complete |
| 7 | Magic System | ✅ Complete (steps 7.0-7.10) |
| 8 | Stores | ✅ Complete |
| 9 | Save/Load and Game Polish | ✅ Complete (9.1-9.4, BUG-1 through BUG-18 fixed) |
| R3.5 | Creature Tier System + REU | ✅ Complete (R3.5.1-R3.5.12, 120 creatures across 5 tiers) |
| R1.1 | Ranged Combat | ✅ Complete — bows, crossbows, slings, 3 ammo types, fire command, ammo stacking |
| R3.4 | Monster Fleeing | ✅ Complete — flee threshold (HP/4) at spawn, reversed greedy movement |
| R2.1 | Special Rooms | ✅ Complete — pits, vaults, nests with $F000 banking |
| R4.1 | Ego Items | ✅ Complete — 7 enchanted weapon types with slay/elemental/AC bonuses |
| OPT-1 | Code Size Optimization | ✅ Complete — 182 bytes reclaimed (OPT-1.1 resolved by R7.6) |
| R7 | String Compression (Tier 1) | ✅ Complete — R7.1-R7.3, R7.6 done. 155 strings Huffman-compressed, 888 bytes saved. Tier 2 (R7.4-R7.5) deferred. |
| 10 | C128 Enhancements | Not started |

### Build Stats

- **Test suites:** 21 (263 runtime tests)
- **Compile-time asserts:** 67
- **Source files:** ~42 .s files
- **Program size:** $B4E8 (program_end), CREATURE_BASE at $C020 — **2,872 bytes headroom**
- **PRG file:** 44,266 bytes (43 KB on disk)

### Known Remaining Issues

| # | Severity | Description | Status |
|---|----------|-------------|--------|
| MC4.1 | LOW | No player critical hit system | **Fixed** — `combat_critical_blow` in combat.s implements umoria `playerWeaponCriticalBlow` (2-5x damage based on weapon weight/tohit/class/level) |
| RP15-4 | LOW | BUG-18 re-entry after inventory popup skips state re-validation | **Resolved** — documented in show_inv_and_restore comment; overlay is read-only |
| MC2.2 | LOW | No fractional XP accumulation (integer-only, documented simplification) | Deferred |
| MC2.3 | LOW | Only uses cr_xp_lo (8-bit XP); will need 16-bit for high-tier creatures | **Fixed** — combat_award_xp now uses 16×8→24-bit multiply with cr_xp_hi:cr_xp_lo; generalized ccl_div_24x8 shared with levelup |
| BUG-19b | **HIGH** | XP awards too generous — player levels up too quickly on low dungeon levels | **Fixed** — experience factor (race_xp% + class_xp%) was never applied to thresholds; now computed at character creation (PL_EXPFACT) and used in combat_check_levelup via 16×8→24-bit multiply + div-by-100 |
| BUG-23 | **HIGH** | Players still level up too fast despite BUG-19b fix — XP economy not matching umoria | **Fixed** — root cause: missing XP halving on multi-level gain. Umoria halves excess XP above each new threshold on level-up; we preserved full XP, allowing cascading (e.g., 150 XP: 1→7 without halving vs 1→4 with). Audit confirmed cr_xp values and xp_level thresholds match umoria exactly. |
| BUG-20 | LOW | ~~Dead string `mat_dead_str` wastes 21 bytes~~ | ✅ Fixed — eliminated by R7.6 Huffman migration |
| BUG-21 | LOW | Acid attack effect is a no-op (no player message) | **Fixed** — prints "SPITS ACID ON YOU" via mon_atk_build_effect_msg |
| BUG-22 | LOW | ~~`mat_the_str` duplicates `cmb_the_str + 1`~~ | ✅ Fixed — OPT-1.7 |
| BUG-24 | **HIGH** | Huffman decoder 8-bit overflow for string IDs >= 128 | **Fixed** — `huff_decode_string` used `txa; asl; tax` for word index, but `asl` overflows for IDs >= 128 (e.g., 154 → offset $34 instead of $134). 27 strings (128-154) decoded wrong text. Fixed with carry-based page branching. |
| BUG-25 | MED | Inventory commands (Wear, Cast, etc.) show all items instead of filtering to applicable ones | **Fixed** — Added `uinv_filter` variable to `ui_inventory.s`. `show_inv_and_restore` accepts filter in A: `$FF`=all (drop, throw, 'I'), `$FE`=wearable (wear), or exact `ICAT_*` match (quaff=potion, read=scroll, aim=wand, use=staff, study=book). Takeoff uses new `show_equip_and_restore` to show equipment instead. ~66 bytes. |
| BUG-26 | MED | -MORE- prompt placement and frequency feels unnatural on 40-column display | **Fixed** — Expanded message area from 1 row to 2 rows (rows 0-1). Messages fill row 0 then row 1; -MORE- only triggers when a 3rd message arrives while both rows are occupied, roughly halving -MORE- frequency. -MORE- positioned at end of row 1 message. Viewport shrunk from 20 to 19 rows (VIEWPORT_Y=2, VIEWPORT_H=19). |
| BUG-27 | MED | Spell casting animation/combat happens while spell list overlay is still displayed | **Fixed** — After player selects a spell letter in `pm_do_cast`, the dungeon screen is restored (`ui_help_clear_all` + viewport + render + status) before any mana/level checks or spell effect dispatch. Bolt animations, damage messages, and error messages now appear on the dungeon screen. Cancel (ESC/space) still handled by main.s `screen_clear`. ~16 bytes. |
| BUG-28 | MED | XP still too generous at low levels — single kills can cause 1-2 level jumps | **Fixed** — Capped `combat_check_levelup` at 1 level-up per kill by replacing the recursive `jmp combat_check_levelup` with `rts`. Excess XP is still halved and retained, so the player levels again on the next kill if still above threshold. Root cause: spawn window [dlvl-2, dlvl+3] allows cr_level 3-4 creatures at DL 1, and XP formula `(cr_xp * cr_level) / player_level` amplifies rewards when cr_level >> player_level. Saves 2 bytes. |
| BUG-30 | **HIGH** | Combat messages corrupted (garbled PETSCII) for tier-loaded creature names | ✅ Fixed — Root cause: stale KERNAL file table (file #2 not closed after LOAD). Added CLOSE+CLRCHN after every KERNAL LOAD; reset `current_tier` on failure. |
| BUG-31 | LOW | Garbage text on screen row 24 during dungeon exploration | ✅ Fixed — Added INPUT_ROW clear to `status_draw` so all code paths clean row 24. |
| OPT-1 | MED | ~~Code size optimization~~ — 182 bytes reclaimed (OPT-1.2–1.7), OPT-1.1 resolved by R7.6 | ✅ Done |
| OPT-2 | MED | ~~Phase overlay code banking~~ — `$E000` overlays + `$F000` UI screens, ~6.8KB freed. Display bugs from incorrect banking ($34→$35) fixed. | ✅ Done |

### What's Next

Priority order based on AUDIT review (see Audit Response below):

| Priority | # | What | Effort |
|----------|---|------|--------|
| ~~1~~ | A1 | ~~File naming cleanup~~ — ✅ THE.GAME, HALL.OF.FAME, MONSTER.DB.1-4 | Done |
| ~~2~~ | A2 | ~~Directory art~~ — ✅ PETSCII title card in d64 directory listing | Done |
| ~~3~~ | A5 | ~~Stack depth audit (trace deep call chains)~~ — ✅ Max 27 bytes (11%), safe | Done |
| ~~4~~ | A3 | ~~Character disk strategy (separate game/save disks)~~ — ✅ Dual-disk mode with swap prompts | Done |
| ~~5~~ | R3.4 | ~~Monster fleeing at low HP~~ — ✅ Flee threshold (HP/4) at spawn, reversed greedy movement | Done |
| ~~6~~ | R2.1 | ~~Special rooms (vaults, pits, nests)~~ — ✅ Pits, vaults, nests with $F000 banking | Done |
| ~~7~~ | R4.1 | ~~Ego items~~ — ✅ 7 enchanted weapon types with slay/elemental/AC bonuses | Done |
| ~~8~~ | OPT-1 | ~~Code size optimization~~ — ✅ 182 bytes reclaimed ($BFF7→$BF41), 20/20 tests pass | Done |
| ~~9~~ | OPT-2 | ~~Code banking~~ — ✅ Phase overlays at `$E000` + permanent `$F000` expansion. ~6.8KB freed. Display bugs fixed (color RAM, input banking, filesystem naming). | Done |
| ~~10~~ | R5.1/R5.2 | ~~Spell expansion~~ — ✅ All 32 effects implemented. 8 spellbooks (4/class), book-gated learning, books not consumed. +101 bytes. | Done |
| ~~11~~ | R6.1 | ~~Store haggling~~ — ✅ Multi-round buy/sell haggling with insult/kick system. CHR affects markup. Items ≤10 GP use simple Y/N. Number input, 4-round negotiation, gap/step convergence. +1479 bytes in town overlay ($E000-$EF47). | Done |
| ~~12~~ | R7.1-R7.2 | ~~Huffman codec + resident compressed strings (Tier 1)~~ — ✅ 155 strings, 888 bytes saved (program_end $B196→$AE1E) | Done |
| ~~13~~ | R7.3 | ~~Store dialog strings~~ — ✅ 15 shopkeeper insults compressed via Huffman | Done |
| ~~14~~ | R7.6 | ~~Combat/UI string migration~~ — ✅ 155 strings from 11 source files, 3 migration patterns | Done |
| **15** | R7.4-R7.5 | Overlay string banks + REU cache (Tier 2 — when Tier 1 space exhausted) | Medium |
| **16** | A4 | Separate binaries (BOOT.PRG + MORIA64 + MORIA128) | Major (Phase 10) |

**Lower priority content** (all now done):
~~R1.2 Throwing~~ ✅, ~~R3.2 Group tactics~~ ✅, ~~R3.3 Breeders~~ ✅, ~~R4.4 Pseudo-ID~~ ✅, ~~R6.2 Black Market~~ ✅, ~~R6.3 Player Home~~ ✅

**Remaining TODO features** (prioritized by complexity/benefit — all confirmed in umoria source):

| Priority | ID | Feature | Complexity | Benefit | Notes |
|----------|-----|---------|-----------|---------|-------|
| ~~1~~ | ~~R4.6~~ | ~~Flasks of Oil~~ | ~~Low~~ | ~~Medium~~ | ✅ **DONE** — SHIFT+R refuel command, item type 61, store/equip support. |
| ~~2~~ | ~~R1.7~~ | ~~Bash command~~ | ~~Medium~~ | ~~High~~ | ✅ **DONE** — SHIFT+D bash command. Door bash (STR-based chance), monster bash (shield weight to-hit, 1d4+STR+3 damage, stun check), off-balance paralysis. 6 tests in test_bash.s. |
| 3 | R2.5 | Tunneling + treasure veins | Medium | High | T command (dig through walls/veins), treasure in quartz/magma veins, wall-to-mud spell fix. Core umoria mechanic currently missing. |
| 4 | R7.4-R7.5 + R7.7 | Monster recall | High | High | Full system: recall data structures, combat tracking (kills/spells/attacks), save/load persistence, `/` display command, string bank infrastructure for recall text. Signature Moria feature but large scope. |

**Phase 10 — C128 Enhancements** (not started):

| # | What | Summary |
|---|------|---------|
| 10.1 | 80-column VDC mode | Second rendering backend for VDC 80x25 display |
| 10.2 | Extended memory | C128 128KB MMU bank-switch path (no disk tier loading) |
| 10.3 | Larger dungeon | Expand map to 120x80+, more rooms, up to 64 active monsters |
| 10.4 | Enhanced display | VDC color attributes for threat-coded monsters |

---

### Priority Triage (updated 2026-02-17)

**Completed since original triage:**
- ~~R1.1 Ranged combat~~ — ✅ ranged_fire.s (bows, crossbows, slings, ammo stacking)
- ~~R1.3 Monster attacks~~ — ✅ Phase 5.4
- ~~R1.4 Monster spells~~ — ✅ Phase 7.8 (monster_magic.s)
- ~~R2.2 Mineral streamers~~ — ✅ 5 streamers per level (3 magma + 2 quartz)
- ~~R2.4 Secret doors~~ — ✅ Phase 4.6 (place_secrets + do_search)
- ~~R3.5 Creature roster~~ — ✅ R3.5.1-R3.5.12 (120 creatures, 5 tiers, REU + disk)
- ~~A1 File naming~~ — ✅ THE.GAME, HALL.OF.FAME, MONSTER.DB.1-4
- ~~A2 Directory art~~ — ✅ PETSCII title card via tools/diskart.py

**High priority (from AUDIT — polish & release readiness):**
- ~~A5 Stack depth audit~~ — ✅ max 27 bytes (11%), safe, no canary needed
- ~~A3 Character disk strategy~~ — ✅ dual-disk mode with swap prompts

**Medium priority (significant missing content):**
- ~~R3.4 Monster fleeing~~ — ✅ Done
- ~~R2.1 Special rooms~~ — ✅ Done (pits, vaults, nests with $F000 banking)
- ~~R4.1 Ego items~~ — ✅ Done
- ~~R5.1/R5.2 Spell expansion~~ — ✅ Done (8 spellbooks, book-gated learning)
- ~~R6.1 Store haggling~~ ✅

**Medium priority (missing core mechanic):**
- R2.5 Tunneling + treasure veins — T command, STR-based digging, gold in quartz/magma, wall-to-mud fix

**Medium priority (infrastructure for more content):**
- ~~R7.1-R7.2 Huffman codec + resident compressed strings~~ ✅
- ~~R7.3 Store dialog strings~~ ✅
- R7.4-R7.5 Overlay string banks + REU cache — Tier 2, when resident space is exhausted

**Medium priority (missing core command):**
- ~~R1.7 Bash~~ ✅ — SHIFT+D bash command (door/monster bash with stun)

**Low priority (polish/completeness):**
- ~~R1.2 Throwing~~ ✅
- ~~R3.2 Group tactics~~ ✅
- ~~R3.3 Breeders~~ ✅
- ~~R4.4 Pseudo-ID~~ ✅
- ~~R4.6 Flasks of Oil~~ ✅
- ~~R7.6 Combat/UI string migration~~ ✅
- R7.7 Monster recall — full feature (data structures + tracking + display + string banks)
- ~~R6.2 Black Market~~ ✅
- ~~R6.3 Player Home~~ ✅
- A4 Separate binaries — Phase 10 scope (BOOT.PRG + MORIA64 + MORIA128)
- A6 Large file split — opportunistic refactoring (dungeon_gen.s, item.s)
- A7 Item generation distribution review vs umoria curves

---

## Town Overlay Size Optimization — OPT-3 (2026-02-18)

### Problem

The town overlay (`$E000-$EFFF`, 4096 bytes max) is at **4,074 bytes** — only **22 bytes free**. Any new feature or bug fix that adds code to `store.s` or `ui_store.s` risks overflowing. This plan identifies strategies to reclaim space without losing functionality.

### Current Breakdown

| Category | Bytes | % of overlay |
|----------|-------|-------------|
| Raw string data (46 strings) | 661 | 16.2% |
| Pointer tables + misc data | ~108 | 2.7% |
| Code (logic + UI boilerplate) | ~3,305 | 81.1% |
| **Total** | **4,074** | **99.5%** |

The code portion is dominated by repetitive UI boilerplate: `jsr screen_put_string` is called **34 times**, `jsr store_clear_msg_area` **16 times**, and the "set color, set row, set col, load string pointer" pattern repeats ~25 times at 20-28 bytes each.

### OPT-3.1 — Parameterized Message Display Helper (~300-400 bytes saved)

**Highest impact.** The repeated pattern in `ui_store.s`:

```asm
    lda #COL_xxx
    sta zp_text_color
    lda #row
    sta zp_cursor_row
    lda #col
    sta zp_cursor_col
    lda #<string
    sta zp_ptr0
    lda #>string
    sta zp_ptr0_hi
    jsr screen_put_string
```

costs 20-28 bytes per occurrence (~25 occurrences = 500-700 bytes total). Replace with a table-driven helper:

```asm
// Message descriptor table: 5 bytes per entry (color, row, col, str_lo, str_hi)
msg_table:
    .byte COL_WHITE, 20, 1, <uis_buy_which_str, >uis_buy_which_str  // MSG_BUY_WHICH
    .byte COL_RED,   22, 1, <uis_no_afford_str, >uis_no_afford_str  // MSG_NO_AFFORD
    // ... etc

// Helper: X = message ID (0-based)
show_msg:
    txa
    asl
    asl
    clc
    adc msg_table_idx,x   // or compute ×5
    tax
    lda msg_table+0,x
    sta zp_text_color
    lda msg_table+1,x
    sta zp_cursor_row
    lda msg_table+2,x
    sta zp_cursor_col
    lda msg_table+3,x
    sta zp_ptr0
    lda msg_table+4,x
    sta zp_ptr0_hi
    jmp screen_put_string
```

Each call site shrinks from ~20-28 bytes to **5 bytes** (`ldx #MSG_ID; jsr show_msg`). Helper cost: ~35 bytes + 5 bytes per table entry.

- ~25 applicable call sites × ~23 bytes saved per site = ~575 bytes saved
- Overhead: 35 byte helper + 25 × 5 byte table entries = 160 bytes
- **Net savings: ~300-400 bytes**

Note: Some call sites interleave price display between string prints (e.g., `sbuy_show_price` prints "PRICE: ", then a number, then " GP. BUY? (Y/N)"). These compound patterns need a `show_msg` call for the first part, then inline code for the number, then another `show_msg` or inline for the suffix. Not every occurrence can be fully parameterized, but most can.

### OPT-3.2 — Merge haggle_buy / haggle_sell (~150-170 bytes saved)

`haggle_buy` (lines 994-1188 of `ui_store.s`) and `haggle_sell` (lines 1198-1396) are structurally nearly identical. Differences:

| Aspect | haggle_buy | haggle_sell |
|--------|-----------|------------|
| Accept condition | `input >= ask` | `input <= ask` |
| Counter step | `ask -= step` (toward min) | `ask += step` (toward max) |
| Insult threshold | `input < min/2` | `input > 2×max` |
| Display strings | "ASKS" / "YOUR OFFER?" | "OFFERS" / "YOUR PRICE?" |

Merge into a single `haggle_common` with a `hg_mode` flag (0=buy, 1=sell):

```asm
hg_mode: .byte 0   // 0=buy, 1=sell

haggle_common:
    lda #0
    sta hg_round
!hc_loop:
    lda hg_mode
    beq !hc_buy_display+
    jsr hg_show_offer       // sell display
    jmp !hc_get_input+
!hc_buy_display:
    jsr hg_show_ask         // buy display
!hc_get_input:
    jsr input_read_number
    // ... shared insult/accept/counter logic with mode-based branches
```

The insult, kick, accept, and counter-offer-with-clamp logic is identical except for comparison direction and add/subtract. A few `lda hg_mode; beq` branches (5 bytes each × ~4 branch points = 20 bytes) replace ~180 bytes of duplicated code.

`hg_show_sell_counter` and `hg_show_sell_final` already just `jmp` to their buy counterparts, confirming the display code is already shared.

- Duplicate code eliminated: ~180 bytes
- Mode-branch overhead: ~20-30 bytes
- **Net savings: ~150-170 bytes**

### OPT-3.3 — Huffman-Compress Overlay Strings (~200-250 bytes saved)

661 bytes of raw null-terminated strings in the overlay. The Huffman decoder (`huff_decode_string` in `huffman.s`) already lives in main RAM and is callable from the overlay — it's already used for haggling insult strings.

Move store UI strings into the Huffman compressed string table (`huffman_data.s`). At typical ~50-55% compression ratio for short uppercase English strings:

- 661 bytes raw → ~330-360 bytes compressed
- String IDs added to `huff_str_index` (2 bytes each × 46 strings = 92 bytes, but in main RAM not overlay)
- Call overhead per string: `ldx #STR_ID; jsr huff_decode_string; jsr screen_put_string` = 8 bytes, roughly same as current inline pointer load (8 bytes for `lda #<str; sta zp_ptr0; lda #>str; sta zp_ptr0_hi`)

The raw string data is removed from the overlay entirely. The compressed data lives in main RAM (inside `huffman_data.s`). Cost is only the string IDs being added to the Huffman encoder pipeline (`tools/huff_encoder.py`).

- 661 bytes removed from overlay
- ~92 bytes of index overhead added to main RAM (not overlay)
- ~330-360 bytes of compressed data added to main RAM (not overlay)
- **Net overlay savings: ~600 bytes** (but costs ~420-450 bytes in main RAM)

If main RAM is also tight, a middle ground is to Huffman-compress only the longest strings (owner names: 126 bytes, UI messages: 314 bytes) and keep short strings (like "GP.", "AGREED!") inline.

**Interaction with OPT-3.1:** If strings are Huffman-encoded, the message display helper table stores string IDs instead of raw pointers, and calls `huff_decode_string` before `screen_put_string`. These two optimizations compose well.

### OPT-3.4 — Replace Separator String with Draw Loop (~26 bytes saved)

The 40-dash separator string (`uis_sep_str`) is 41 bytes and used twice. Replace with:

```asm
draw_separator:
    ldx #40
!:  lda #$2d           // '-' screen code
    jsr screen_put_char
    dex
    bne !-
    rts                 // 12 bytes
```

Remove the 41-byte string, add 12 bytes of code. Two call sites change from `lda #<uis_sep_str; sta zp_ptr0; lda #>uis_sep_str; sta zp_ptr0_hi; jsr screen_put_string` (11 bytes) to `jsr draw_separator` (3 bytes), saving an additional 16 bytes.

- **Net savings: ~26 bytes** (trivial effort, zero risk)

### OPT-3.5 — Move Store Names/Owners Out of Overlay (~80-126 bytes saved)

Store names (82 bytes with nulls) and owner names (126 bytes with nulls) plus their pointer tables (32 bytes) are only used during `store_draw_screen`. Options:

**Option A: Huffman-encode into main RAM string table.** Part of OPT-3.3. Removes 208 bytes of string data + 32 bytes of pointer tables from overlay.

**Option B: Shorten owner strings.** Trim titles: "BILBO THE FRIENDLY" → "BILBO", "GORN THE ARMORER" → "GORN", etc. Saves ~80 bytes but reduces flavor. Not recommended as a standalone change.

**Option C: Move raw strings to main RAM.** Store name/owner strings live in `store_data.s` (main RAM) instead of the overlay. The pointer tables also move. The overlay code references them via the same labels. Cost: 240 bytes of main RAM. Savings: 240 bytes of overlay.

- **Net overlay savings: 80-240 bytes** depending on approach

### OPT-3.6 — Factor Cancel-Key Check (~15 bytes saved)

The Q/ESC/SPACE cancel pattern appears 3 times (`store_buy`, `store_sell`, `input_read_number`):

```asm
    cmp #PETSCII_Q
    bne !not_q+
    rts
!not_q:
    cmp #PETSCII_ESC
    bne !not_esc+
    rts
!not_esc:
    cmp #PETSCII_SPACE
    bne !not_spc+
    rts
!not_spc:
```

15 bytes each × 3 = 45 bytes. Replace with:

```asm
// check_cancel — carry set = cancel key pressed
check_cancel:
    cmp #PETSCII_Q
    beq !yes+
    cmp #PETSCII_ESC
    beq !yes+
    cmp #PETSCII_SPACE
    bne !no+
!yes:
    sec
    rts
!no:
    clc
    rts              // 16 bytes
```

Each call site becomes `jsr check_cancel; bcs cancel_target` (5 bytes vs 15 bytes).

- 3 × 15 = 45 bytes → 16 + 3 × 5 = 31 bytes
- **Net savings: ~15 bytes** (trivial effort)

### OPT-3.7 — Unify BM + Normal Price Calculation (~30-50 bytes saved)

`calc_bm_buy_price` and `calc_buy_price` share structure: load base cost, multiply by factor, divide, add p1 bonus. Same for the sell paths. The BM paths use fixed multipliers (×3 for buy, ÷10 for sell) while normal paths use CHR-indexed multipliers.

Could parameterize with a multiplier value passed in X:

```asm
// Unified: calc_buy_price_with_factor
// Input: A = item type, X = multiplier (or 0 to use CHR lookup)
calc_buy_price_common:
    sta sb_item_type
    // ... shared setup ...
    cpx #0
    beq !chr_lookup+
    // BM path: use X directly
    jmp !multiply+
!chr_lookup:
    lda player_data + PL_CHR_CUR
    jsr stat_bonus_index
    lda chr_price_adj,x
    tax
!multiply:
    jsr math_mul_16x8
    // ... shared remainder ...
```

- **Net savings: ~30-50 bytes**

### OPT-3.8 — Loop-Based store_clear_msg_area (~8 bytes saved)

Currently 4 sequential `jsr screen_clear_row` calls (12 bytes). Replace with:

```asm
store_clear_msg_area:
    lda #20
!:  jsr screen_clear_row
    clc
    adc #1
    cmp #24
    bcc !-
    rts             // ~10 bytes vs 17 bytes (4×jsr + rts)
```

Called 16 times so keeping it small helps. **Net savings: ~7-8 bytes.**

### Priority and Implementation Order

| Priority | Item | Effort | Savings | Cumulative Free |
|----------|------|--------|---------|----------------|
| 1 | OPT-3.4 Separator draw loop | Trivial | ~26 | 48 |
| 2 | OPT-3.6 Cancel-key helper | Trivial | ~15 | 63 |
| 3 | OPT-3.8 Clear-msg loop | Trivial | ~8 | 71 |
| 4 | OPT-3.1 Message display helper | Medium | ~300-400 | 371-471 |
| 5 | OPT-3.2 Merge haggle routines | Medium | ~150-170 | 521-641 |
| 6 | OPT-3.7 Unify price calcs | Low | ~30-50 | 551-691 |
| 7 | OPT-3.5 Move names/owners out | Low-Med | ~80-240 | 631-931 |
| 8 | OPT-3.3 Huffman compress strings | High | ~200-600 | 831-1531 |

Start with the trivial wins (OPT-3.4, 3.6, 3.8) for immediate breathing room (~49 bytes). Then OPT-3.1 for the largest single improvement. OPT-3.2 and OPT-3.7 are good follow-ups. OPT-3.3 and OPT-3.5 are the nuclear options if more room is still needed — they shift bytes from overlay to main RAM.

**Realistic target:** OPT-3.1 through OPT-3.7 should yield **~500-700 bytes free** in the overlay, enough for significant new store features.

---

## Codebase-Wide Size Optimization — OPT-4 (2026-02-18)

### Current State

Main segment: **$080E–$B4CF** (44,225 bytes, ~2,833 bytes before $C000 MAP_BASE).
$F000 banked region: 3,369 of ~4,089 bytes used (~720 bytes free).
Town overlay: 4,074 of 4,096 bytes (22 free — covered by OPT-3).

The main segment has reasonable headroom but adding major features will require optimization. This section identifies cross-module duplication and data compression opportunities that collectively could save **~1,500–2,200 bytes** in the main segment.

### OPT-4.1 — Shared Projectile Trace Loop (~150-180 bytes saved)

Three files contain nearly identical projectile trace loops:

| File | Function | Lines | Pattern |
|------|----------|-------|---------|
| `ranged_fire.s` | `!rf_trace` | 112-161 | Step in direction → bounds check → walkability check → monster_find_at |
| `throw.s` | `!tw_trace` | 160-215 | Identical + saves last walkable position |
| `spell_effects.s` | `!eb_trace` | 562-683 | Identical + bolt animation overlay |

The core trace loop is ~50 bytes each: direction step (8 bytes), bounds check (12 bytes), map tile walkability via `walkable_table` (18 bytes), `monster_find_at` call (6 bytes). All three use the same variable pattern: `*_cx`, `*_cy`, `*_dir`, `*_steps`.

**Fix:** Create a shared `trace_projectile` routine:

```asm
// Input: proj_cx/cy = start, proj_dir = direction, proj_steps = max range
// Output: carry SET = hit monster (X = slot), carry CLEAR = blocked/OOB
//         proj_cx/cy = final position
proj_cx:    .byte 0
proj_cy:    .byte 0
proj_dir:   .byte 0
proj_steps: .byte 0
proj_last_x: .byte 0    // Last walkable position (for throw drop)
proj_last_y: .byte 0

trace_projectile:
    dec proj_steps
    beq !tp_oob+
    ldx proj_dir
    lda proj_cx
    clc
    adc dir_dx,x
    sta proj_cx
    lda proj_cy
    clc
    adc dir_dy,x
    sta proj_cy
    // Bounds + walkability + monster check...
    // ~50 bytes total
```

Each caller shrinks from ~50 bytes inline to ~15 bytes of setup + `jsr trace_projectile`. `throw.s` copies `proj_cx/cy → proj_last_x/y` after each step (4 bytes extra). `spell_effects.s` adds animation code after the walkability check via a callback flag or inline hook.

- 3 × ~50 = 150 bytes inline → 50 byte helper + 3 × 15 = 95 bytes
- **Net savings: ~55 bytes** (conservative, more with the direction-finding code below)

### OPT-4.2 — Shared Direction-Finding from Target (~80-100 bytes saved)

Three files contain identical direction-finding code that converts `df_target_x/y` delta into a `dir_dx/dir_dy` table index:

```asm
    lda df_target_x
    sec
    sbc zp_player_x
    sta zp_temp0            // dx
    lda df_target_y
    sec
    sbc zp_player_y
    sta zp_temp1            // dy
    ldx #0
!find_dir:
    lda dir_dx,x
    cmp zp_temp0
    bne !dir_next+
    lda dir_dy,x
    cmp zp_temp1
    beq !dir_found+
!dir_next:
    inx
    cpx #8
    bcc !find_dir-
```

This ~30-byte pattern appears in `ranged_fire.s` (lines 78-101), `throw.s` (lines 97-121), and `spell_effects.s` (lines 526-549).

**Fix:** Extract a shared `calc_direction_index` utility:

```asm
// Input: df_target_x/y (adjacent to player)
// Output: X = direction index 0-7, carry SET = found
calc_direction_index:
    lda df_target_x
    sec
    sbc zp_player_x
    sta zp_temp0
    lda df_target_y
    sec
    sbc zp_player_y
    sta zp_temp1
    ldx #0
!:  lda dir_dx,x
    cmp zp_temp0
    bne !next+
    lda dir_dy,x
    cmp zp_temp1
    beq !found+
!next:
    inx
    cpx #8
    bcc !-
    clc
    rts
!found:
    sec
    rts
```

~35 byte helper, each call site becomes `jsr calc_direction_index; bcc cancel; stx *_dir` (~8 bytes).

- 3 × ~30 = 90 bytes → 35 + 3 × 8 = 59 bytes
- **Net savings: ~30 bytes**

Combined with OPT-4.1 (shared trace loop, shared direction finding, shared scratch vars), total savings ~**150-180 bytes**.

### OPT-4.3 — Unify Adjacent-Tile Iteration (~120-150 bytes saved)

`spell_effects.s` has **four** separate 8-direction adjacent-tile loops with identical structure:

| Function | Lines | Action per direction |
|----------|-------|---------------------|
| `eff_sleep_adjacent` | 420-455 | find_at → set MX_SLEEP_CUR |
| `eff_confuse_adjacent` | 463-497 | find_at → set MX_CONFUSE |
| `eff_damage_adjacent` | 775-836 | find_at → roll dice → subtract HP → death check |
| `eff_destroy_traps_doors` | 864-980 | read tile → modify tile (TWO separate 8-dir loops!) |

Each loop follows the identical skeleton (~35 bytes):

```asm
    lda #0
    sta *_dir
!loop:
    lda *_dir
    cmp #8
    bcs !done+
    tax
    lda zp_player_x
    clc
    adc dir_dx,x
    sta df_target_x
    lda zp_player_y
    clc
    adc dir_dy,x
    ...action...
    inc *_dir
    jmp !loop-
!done:
    rts
```

**Fix:** Create `for_each_adjacent(callback)` using a function pointer or inline dispatch:

```asm
// Iterates 8 directions, for each: sets df_target_x/y, calls callback via JMP indirect
adj_callback: .word 0   // Function pointer

for_each_adjacent:
    lda #0
    sta adj_dir_idx
!fea_loop:
    lda adj_dir_idx
    cmp #8
    bcs !fea_done+
    tax
    lda zp_player_x
    clc
    adc dir_dx,x
    sta df_target_x
    lda zp_player_y
    clc
    adc dir_dy,x
    sta df_target_y
    jsr !fea_dispatch+
    inc adj_dir_idx
    jmp !fea_loop-
!fea_done:
    rts
!fea_dispatch:
    jmp (adj_callback)
```

Helper: ~40 bytes. Each call site becomes: set callback pointer (6 bytes) + `jsr for_each_adjacent` (3 bytes) + callback body (varies, ~10-15 bytes). The 5 loops of ~35 bytes each become 5 × 9 + 40 = 85 bytes.

- 5 × ~35 = 175 bytes → ~85 bytes
- **Net savings: ~90 bytes**

Alternative (simpler, no function pointers): factor out only the "find monster at adjacent direction" pattern shared by sleep/confuse/damage into a single `for_each_adjacent_monster` that provides X=slot for each found monster. Saves ~70 bytes from just those three.

### OPT-4.4 — Inline Monster HP Damage + Death Check → Shared Subroutine (~80-100 bytes saved)

The pattern "subtract damage from monster HP via `(zp_ptr0),y` + check dead" appears **three times** inline in `spell_effects.s` (eff_bolt line 704-720, eff_damage_adjacent line 810-825, eff_dispel_undead line 1084-1100) and once as the existing `combat_apply_damage` in `combat.s` (line 671-703).

The inline versions duplicate ~25 bytes each and differ only in the damage source register (zp_math_a/b vs A):

```asm
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    sec
    sbc zp_math_a
    sta (zp_ptr0),y
    ldy #MX_HP_HI
    lda (zp_ptr0),y
    sbc zp_math_b
    sta (zp_ptr0),y
    bmi !dead+
    ldy #MX_HP_LO
    lda (zp_ptr0),y
    ldy #MX_HP_HI
    ora (zp_ptr0),y
    bne !alive+
```

**Fix:** Extend `combat_apply_damage` to accept 16-bit damage (currently only 8-bit via A register). Or create a `combat_apply_damage_16` variant that reads from zp_math_a/b. The inline code in spell_effects.s then becomes `jsr combat_apply_damage_16` (3 bytes each).

- 3 × ~25 = 75 bytes inline → 25 byte helper + 3 × 3 = 34 bytes
- **Net savings: ~40 bytes** (plus cleaner code)

### OPT-4.5 — Unify combat_calc_tohit / throw_calc_tohit (~100-120 bytes saved)

`combat.s:combat_calc_tohit` (lines 168-257, ~90 bytes) and `throw.s:throw_calc_tohit` (lines 417-516, ~100 bytes) are structurally identical. The only differences:

| Aspect | combat_calc_tohit | throw_calc_tohit |
|--------|------------------|-----------------|
| Class property offset | BTH (offset 3) | BTH_BOW (offset 4) |
| Level adj offset | class_level_adj+0 | class_level_adj+1 |
| Post-processing | None | × 75% (×3 >> 2) |

**Fix:** Parameterize with a "BTH offset" passed in A or a ZP var:

```asm
// Input: A = class property offset (3=melee, 4=bow)
//        X = level adj offset (0=melee, 1=bow)
combat_calc_tohit_common:
    sta cct_prop_offset
    stx cct_lvl_offset
    // ... shared code (~90 bytes) ...
    rts

// throw_calc_tohit wrapper: calls common then applies 75%
throw_calc_tohit:
    lda #4
    ldx #1
    jsr combat_calc_tohit_common
    // 75% = *3/4
    lda zp_combat_tohit
    sta zp_temp0
    asl
    bcs !cap+
    clc
    adc zp_temp0
    bcc !div+
!cap: lda #255
!div: lsr
    lsr
    sta zp_combat_tohit
    rts
```

The 75% wrapper is ~20 bytes. The shared routine is ~90 bytes. Eliminates ~100 bytes of throw.s duplication.

- 90 + 100 bytes → 90 + 20 = 110 bytes
- **Net savings: ~80 bytes**

### OPT-4.6 — Table-Driven Effect Timer Ticks (~60-80 bytes saved)

`turn.s:turn_tick_effects` (lines 20-208) has 13 individual effect timers. Most follow one of two patterns:

**Pattern A — Simple decrement (7 timers: speed, protect, invis, infra, bless, hero, regen):**
```asm
    lda zp_eff_xxx
    beq !no_xxx+
    dec zp_eff_xxx
!no_xxx:
```
6 bytes each × 7 = 42 bytes. (Speed is slightly different — signed decrement — but the rest are identical.)

**Pattern B — Decrement with expiry message (5 timers: poison, blind, confuse, paralyze, fear):**
```asm
    lda zp_eff_xxx
    beq !no_xxx+
    dec zp_eff_xxx
    bne !no_xxx+   // or bne !still_xxx+
    ldx #HSTR_EFF_XXX_END
    jsr huff_decode_string
    jsr msg_print
!no_xxx:
```
~15 bytes each × 4 = 60 bytes (poison has extra HP damage logic, excluded).

**Fix for Pattern A:** Loop through a table of ZP addresses:

```asm
simple_effect_addrs:
    .byte zp_eff_protect, zp_eff_invis, zp_eff_infra
    .byte zp_eff_bless, zp_eff_hero, zp_eff_regen
.const SIMPLE_EFFECT_COUNT = 6

tick_simple_effects:
    ldx #SIMPLE_EFFECT_COUNT - 1
!loop:
    ldy simple_effect_addrs,x
    lda $00,y               // ZP indirect read
    beq !skip+
    dec $00,y               // ZP indirect decrement
!skip:
    dex
    bpl !loop-
    rts
```

~20 bytes replaces 36 bytes (6 × 6). Savings: ~16 bytes.

**Fix for Pattern B:** Loop through paired table (address, huff ID):

```asm
msg_effect_addrs:
    .byte zp_eff_blind, zp_eff_confuse, zp_eff_paralyze
msg_effect_hstr:
    .byte HSTR_EFF_BLIND_END, HSTR_EFF_CONFUSE_END, HSTR_EFF_PARALYZE_END
.const MSG_EFFECT_COUNT = 3

tick_msg_effects:
    ldx #MSG_EFFECT_COUNT - 1
!loop:
    stx tte_save_x
    ldy msg_effect_addrs,x
    lda $00,y
    beq !skip+
    dec $00,y
    bne !skip+
    ldx tte_save_x
    lda msg_effect_hstr,x
    tax
    jsr huff_decode_string
    jsr msg_print
    ldx tte_save_x
!skip:
    dex
    bpl !loop-
    rts
```

~35 bytes replaces 45 bytes (3 × 15). Savings: ~10 bytes.

Fear and speed have special behavior (fear uses non-ZP `eff_fear_timer`; speed has signed increment logic) — keep those inline.

- **Total savings: ~26 bytes** (modest, but reduces maintenance burden for adding new effects)

### OPT-4.7 — Huffman-Encode Item Name Strings (~300-400 bytes saved)

`item.s` contains **110 raw `.text` strings** for item names totaling ~806 bytes (names only) + 124 bytes of pointer tables = **~930 bytes**. These are looked up via `it_name_lo/hi` tables.

The Huffman infrastructure already exists in main RAM. Item names are short uppercase English strings — the same character distribution as existing Huffman data. At ~55% compression:

- 806 bytes raw → ~445 bytes compressed
- Pointer tables (110 × 2 = 220 bytes) become index entries in the Huffman string table
- Decode call overhead: name lookup changes from pointer dereference to `huff_decode_string` call

The `item_get_name_ptr` function currently returns a raw pointer. After Huffman encoding, it would decode to `hd_decode_buf` and return a pointer to that. Callers already use the returned pointer with `screen_put_string` — no change needed.

- 930 bytes → ~445 compressed + ~220 index entries (already absorbed by Huffman table)
- **Net savings in main segment: ~300-400 bytes**

Note: Since `hd_decode_buf` is reused, callers that need to retain the name across another decode call would need to copy it first. Audit all `item_get_name_ptr` call sites.

### OPT-4.8 — Remaining Raw Strings to Huffman (~100-120 bytes saved)

Several modules still contain small raw strings that could be Huffman-encoded:

| File | Strings | Bytes |
|------|---------|-------|
| `turn.s` | pid_w_terrible/bad/average/good/excellent + pid_sense_str | 50 |
| `combat.s` | cmb_you_str, cmb_the_str, cmb_hit_str, cmb_miss_str, cmb_kill_str, cmb_period | 33 |

The `combat.s` strings are heavily used by `combat_append_str` which needs raw pointers for inline assembly into `combat_msg_buf`. These are poor Huffman candidates — the decode overhead would exceed the savings for 3-4 byte strings.

The `turn.s` pseudo-ID quality words (50 bytes + 10 bytes pointer tables = 60 bytes) are a better candidate — they're only used in one place. Encoding them saves ~30 bytes.

- **Net savings: ~30 bytes** (only pseudo-ID strings worth converting)

### OPT-4.9 — Deduplicate "Hit Alive / Dead" Message Patterns (~60-80 bytes saved)

After a monster takes damage, four modules repeat the same "dead or alive" message dispatch:

```asm
// Dead path:
    ldx slot
    jsr eff_kill_monster
    lda #<cmb_kill_str
    ldy #>cmb_kill_str
    jsr msg_build_action    // "YOU HAVE SLAIN THE <name>."
    jsr cmb_print_buf
    lda #SFX_HIT
    jsr sound_play
    rts

// Alive path:
    jsr monster_get_ptr
    ldy #MX_FLAGS
    lda (zp_ptr0),y
    ora #MF_AWAKE
    sta (zp_ptr0),y
    // Build "VERB THE <name>." message
    ...
```

This ~40-byte dead path appears in `combat.s` (line 111-134), `ranged_fire.s` (line 217-225), `throw.s` (line 296-304), and `spell_effects.s` (line 722-732).

**Fix:** Create `combat_kill_message`:
```asm
// Input: cmb_slot, cmb_type already set
// Prints "YOU HAVE SLAIN THE <name>.", plays SFX, awards XP
combat_kill_message:
    ldx cmb_slot
    jsr eff_kill_monster
    lda #<cmb_kill_str
    ldy #>cmb_kill_str
    jsr msg_build_action
    jsr cmb_print_buf
    lda #SFX_HIT
    jmp sound_play         // Tail call
```

~20 bytes. Each of 4 call sites becomes `jsr combat_kill_message` (3 bytes) instead of ~20 bytes inline.

- 4 × 20 = 80 bytes → 20 + 4 × 3 = 32 bytes
- **Net savings: ~48 bytes**

Similarly, the "wake monster" pattern (get_ptr, load flags, ora MF_AWAKE, store) is ~12 bytes and appears 3 times. A `monster_wake` helper saves ~20 bytes.

- **Combined savings: ~68 bytes**

### OPT-4.10 — Projectile Hit/Miss Message Deduplication (~50-60 bytes saved)

`ranged_fire.s` and `throw.s` both build identical hit/miss messages:

```asm
// "THE <item> HITS THE <name>."
    jsr *_msg_item_prefix       // "THE <item>"
    ldx #HSTR_RF_HITS
    jsr huff_append_combat      // " HITS"
    lda #<cmb_the_str
    ldy #>cmb_the_str
    jsr combat_append_str       // " THE "
    jsr combat_append_monster_name
    lda #<cmb_period
    ldy #>cmb_period
    jsr combat_append_str       // "."
    jsr *_print_msg
```

This ~30-byte "append VERB THE name." suffix appears 4 times across the two files (hit + miss for both ranged and throw). The `*_msg_item_prefix` functions are also nearly identical (both build "THE <item>" — differ only in the item ID source).

**Fix:** Create `projectile_msg_suffix(verb_hstr_id)`:
```asm
// Appends " VERB THE <name>." to combat_msg_buf and prints
projectile_msg_suffix:
    jsr huff_append_combat      // VERB
    lda #<cmb_the_str
    ldy #>cmb_the_str
    jsr combat_append_str
    jsr combat_append_monster_name
    lda #<cmb_period
    ldy #>cmb_period
    jsr combat_append_str
    jmp cmb_term_and_print
```

~25 bytes. Replaces 4 × ~25 = 100 bytes with 25 + 4 × 5 = 45 bytes.

- **Net savings: ~55 bytes**

### OPT-4.11 — Huff-Decode-and-Print Helper (~30-40 bytes saved)

The two-line pattern:
```asm
    ldx #HSTR_xxx
    jsr huff_decode_string
    jsr msg_print
```
appears **10 times** across 10 files (turn.s, spell_effects.s, throw.s, bash.s, player_items.s, player_move.s, ranged_fire.s, monster_attack.s, dungeon_features.s, player_magic.s). Each instance is 8 bytes (2 + 3 + 3).

**Fix:** Create `huff_print_msg`:
```asm
// Input: X = Huffman string ID
huff_print_msg:
    jsr huff_decode_string
    jmp msg_print          // 6 bytes
```

Each call site becomes 5 bytes (`ldx #ID; jsr huff_print_msg`) instead of 8 bytes.

- 10 × 8 = 80 bytes → 6 + 10 × 5 = 56 bytes
- **Net savings: ~24 bytes** (trivial to implement)

### Priority and Implementation Order

| Priority | Item | Effort | Est. Savings | Files Affected |
|----------|------|--------|-------------|----------------|
| 1 | OPT-4.11 Huff-print helper | Trivial | ~24 | 10 files |
| 2 | OPT-4.9 Kill/wake message helpers | Low | ~68 | combat.s, ranged_fire.s, throw.s, spell_effects.s |
| 3 | OPT-4.10 Projectile msg dedup | Low | ~55 | ranged_fire.s, throw.s |
| 4 | OPT-4.5 Unify tohit calc | Medium | ~80 | combat.s, throw.s |
| 5 | OPT-4.1+4.2 Shared trace + direction | Medium | ~150-180 | ranged_fire.s, throw.s, spell_effects.s |
| 6 | OPT-4.3 Adjacent-tile iterator | Medium | ~90-120 | spell_effects.s |
| 7 | OPT-4.4 Shared 16-bit HP damage | Low | ~40 | spell_effects.s, combat.s |
| 8 | OPT-4.6 Table-driven effect ticks | Medium | ~26 | turn.s |
| 9 | OPT-4.7 Huffman item names | High | ~300-400 | item.s, huffman_data.s, tools/ |
| 10 | OPT-4.8 Remaining raw strings | Low | ~30 | turn.s |

### Summary

| Category | Items | Total Savings |
|----------|-------|--------------|
| Code deduplication (OPT-4.1–4.6, 4.9–4.11) | 8 items | ~550-650 bytes |
| String compression (OPT-4.7–4.8) | 2 items | ~330-430 bytes |
| **Total** | **10 items** | **~880-1,080 bytes** |

Combined with OPT-3 (town overlay, ~500-700 bytes saved there), the project can reclaim substantial headroom in both the main segment and the overlay without losing any features. The code deduplication items (OPT-4.1–4.6, 4.9–4.11) are recommended first since they also improve maintainability. OPT-4.7 (Huffman item names) is the single largest main-segment win but requires tooling changes.

---

## Tunneling & Treasure Veins — R2.5 (2026-02-18)

### Problem

Magma and quartz streamers are generated during dungeon creation (3 magma + 2 quartz per level) but serve only as impassable obstacles. In umoria, these veins are a core gameplay mechanic: players can tunnel through them with the `T` command, and quartz/magma veins can contain embedded gold treasure. The wall-to-mud spell should also destroy veins. Currently none of this is implemented.

### Umoria Reference

**Tunnel command (`T` + direction):**
- If confused: 75% chance of random direction
- If monster present at target: attack instead of tunneling
- Digging ability = STR + weapon bonus
  - Shovel/Pick: STR + 25 + (50 × enchantment level)
  - Normal weapon: STR + (max_damage + tohit + todam) / 2
  - Bare hands: STR only
- Heavy weapon penalty reduces digging ability
- Success: `digging_ability > wall_resistance` (random per attempt)

**Wall resistance by type:**

| Wall Type | Resistance Range | Relative Difficulty |
|-----------|-----------------|-------------------|
| Granite wall | 80–1,280 | Hardest |
| Magma intrusion | 10–610 | Medium |
| Quartz vein | 10–410 | Easiest |
| Boundary wall | Impossible | Cannot tunnel |

**Treasure in veins (placed during dungeon generation):**

| Vein Type | Treasure Chance Per Tile | Streamers/Level |
|-----------|------------------------|-----------------|
| Magma | 1 in 90 | 3 |
| Quartz | 1 in 40 | 2 |

Quartz has ~2.25× higher treasure density than magma. When a treasure vein tile is tunneled or destroyed by wall-to-mud, gold drops on the floor.

**Wall-to-Mud spell:** Instantly destroys any non-boundary wall type (granite, magma, quartz) along a bolt path. No STR check required. Treasure vein gold still drops.

### Implementation Plan

#### R2.5.1 — Treasure Vein Tile Types

Add two new tile types for treasure-bearing veins. The current tile encoding uses 4-bit type in bits 7-4:

| Tile | Current Value | Notes |
|------|--------------|-------|
| TILE_MAGMA | $C0 | Already exists |
| TILE_QUARTZ | $D0 | Already exists |
| TILE_TRAP | $E0 | Already exists |
| TILE_SECRET | $F0 | Already exists |

**Problem:** All 16 tile type slots (0-15) are taken. Options:

**Option A — Use a flag bit.** The lower nibble (bits 3-0) holds flags (`FLAG_VISITED`, `FLAG_LIT`, `FLAG_HAS_ITEM`, `FLAG_OCCUPIED`). If a flag bit is available, use it as `FLAG_TREASURE` on magma/quartz tiles. Check: `FLAG_HAS_ITEM` (bit 0) is only used on floor tiles for floor items — it could be repurposed on wall tiles to mean "has treasure". This costs zero new tile types.

**Option B — Encode in the map differently.** Use a separate 1-bit-per-tile bitfield for treasure markers. At 64×60 = 3,840 tiles, this needs 480 bytes — too expensive.

**Recommended: Option A** — reuse `FLAG_HAS_ITEM` (bit 0) on magma/quartz tiles to mean "contains treasure." Since items can't exist on impassable tiles, there's no conflict. When the tile is tunneled to floor, clear the flag and spawn gold.

#### R2.5.2 — Treasure Placement in Dungeon Generation

Modify `carve_streamer()` in `dungeon_gen.s` to roll for treasure at each vein tile:

```asm
// After placing TILE_MAGMA or TILE_QUARTZ:
    lda streamer_type
    cmp #TILE_MAGMA
    bne !check_quartz+
    lda #90                     // 1-in-90 chance for magma
    jmp !roll_treasure+
!check_quartz:
    lda #40                     // 1-in-40 chance for quartz
!roll_treasure:
    jsr rng_range               // A = rng(chance)
    cmp #1
    bne !no_treasure+
    ldy map_offset
    lda (zp_ptr0),y
    ora #FLAG_HAS_ITEM          // Set treasure flag on the vein tile
    sta (zp_ptr0),y
!no_treasure:
```

Estimated cost: ~25 bytes in `dungeon_gen.s`.

#### R2.5.3 — Tunnel Command (`T` + direction)

New command `CMD_TUNNEL` mapped to `T` key in `input.s`. Handler in a new `tunnel.s` module (or extend `player_move.s`):

```asm
// player_tunnel: called with direction in zp_input_dir
player_tunnel:
    // 1. Get target tile coordinates
    ldx zp_input_dir
    lda zp_player_x
    clc
    adc dir_dx,x
    sta df_target_x
    lda zp_player_y
    clc
    adc dir_dy,x
    sta df_target_y

    // 2. Check for monster → attack instead
    jsr monster_find_at
    bcc !no_monster+
    jmp player_attack_monster   // Redirect to melee
!no_monster:

    // 3. Get tile type
    jsr map_get_tile            // A = tile byte at target
    and #$F0                    // Isolate type nibble
    // Check tunnelable types
    cmp #TILE_WALL_H
    beq !tunnel_granite+
    cmp #TILE_WALL_V
    beq !tunnel_granite+
    cmp #TILE_MAGMA
    beq !tunnel_magma+
    cmp #TILE_QUARTZ
    beq !tunnel_quartz+
    // Rubble — always succeeds
    cmp #TILE_RUBBLE
    beq !clear_rubble+
    // Boundary walls — permanent
    // ... "THIS SEEMS TO BE PERMANENT ROCK."
    rts

!tunnel_granite:
    // resistance = rng(200) + 40 (scaled down from umoria's 1280 range)
    ...
!tunnel_magma:
    // resistance = rng(80) + 5
    ...
!tunnel_quartz:
    // resistance = rng(60) + 5
    ...
```

**Digging ability (simplified for C64):**

Umoria uses STR + weapon bonuses with shovel/pick special items. Since we don't have shovel/pick item types, simplify to:

```
digging_ability = STR_CUR + weapon_damage_avg + weapon_tohit
```

This gives reasonable progression: a STR 3 character with a basic weapon digs ~6-8, while STR 18 with a good weapon digs ~25-30. Wall resistances are scaled down accordingly from umoria's ranges to fit 8-bit math.

**Success check:** `digging_ability > rng(wall_resistance)`

On success:
1. Replace tile with `TILE_FLOOR | FLAG_VISITED | FLAG_LIT`
2. If tile had `FLAG_HAS_ITEM` set (treasure vein): spawn gold at location
3. Print "YOU TUNNEL INTO THE [GRANITE WALL/MAGMA/QUARTZ VEIN]."
4. Print "YOU HAVE FOUND SOMETHING!" on treasure hit
5. Play `SFX_PICKUP` on treasure hit
6. Consumes a turn (call `turn_post_action`)

On failure:
1. Print "YOU DIG IN THE [wall type]." (no "into" — indicates partial progress)
2. Consumes a turn

#### R2.5.4 — Gold Spawn from Treasure Veins

When a treasure vein is opened (by tunneling or wall-to-mud), spawn a gold pile:

```asm
tunnel_spawn_gold:
    // Gold amount scales with dungeon level (simplified from umoria)
    // base = 5 + dlvl * 3, variance = rng(base) * 2
    lda zp_dungeon_level
    asl                         // × 2
    clc
    adc zp_dungeon_level        // × 3
    clc
    adc #5                      // base = 5 + dlvl*3
    jsr rng_range               // rng(base)
    asl                         // × 2
    clc
    adc #1                      // At least 1 GP
    // ... place gold item on floor at df_target_x/y
```

Uses existing `floor_item_add` infrastructure. Gold amount: ~6-60 GP on DL1, ~15-170 GP on DL10, scaling with depth.

#### R2.5.5 — Fix Wall-to-Mud Spell

Extend `eff_wall_to_mud` in `spell_effects.s` to handle magma and quartz:

```asm
eff_wall_to_mud:
    // Currently only checks TILE_WALL_H and TILE_WALL_V
    // Add:
    cmp #TILE_MAGMA
    beq !destroy_wall+
    cmp #TILE_QUARTZ
    beq !destroy_wall+
    // ... existing wall checks ...
!destroy_wall:
    // Check for treasure flag before clearing
    lda original_tile
    and #FLAG_HAS_ITEM
    beq !no_treasure+
    jsr tunnel_spawn_gold
!no_treasure:
    // Replace with floor
    lda #TILE_FLOOR | FLAG_VISITED | FLAG_LIT
    // ... existing floor placement code ...
```

Estimated cost: ~20 bytes added to `spell_effects.s`.

#### R2.5.6 — Rendering

Treasure veins should be visually distinguishable from plain veins. Options:
- **Color differentiation:** Treasure magma/quartz rendered in yellow instead of the normal vein color (brown/grey). Only when tile is visible/lit.
- **No visual difference:** Player must tunnel speculatively (matches umoria — treasure veins look the same until opened).

**Recommended:** No visual difference (matches umoria behavior). The `FLAG_HAS_ITEM` bit is invisible to the player. Discovery is the reward for tunneling.

The existing `dungeon_render.s` tile rendering for magma ($C0) and quartz ($D0) needs no changes — the flag bits in the low nibble don't affect the screen code lookup (tile type is bits 7-4 only).

### Size Estimate

| Component | Location | Est. Bytes |
|-----------|----------|-----------|
| Treasure placement in `carve_streamer` | dungeon_gen.s | ~25 |
| Tunnel command handler | tunnel.s (new) or player_move.s | ~200 |
| Gold spawn from treasure | tunnel.s | ~40 |
| Wall-to-mud vein fix | spell_effects.s | ~20 |
| Command dispatch + key mapping | main.s, input.s | ~10 |
| Huffman strings (4-5 messages) | huffman_data.s | ~40 compressed |
| **Total** | | **~335 bytes** |

### Implementation Order

| Step | What | Effort | Dependencies |
|------|------|--------|-------------|
| R2.5.1 | FLAG_HAS_ITEM treasure encoding | Trivial | None |
| R2.5.2 | Treasure placement in `carve_streamer` | Low | R2.5.1 |
| R2.5.3 | Tunnel command (T + direction) | Medium | R2.5.1 |
| R2.5.4 | Gold spawn from treasure veins | Low | R2.5.1 |
| R2.5.5 | Wall-to-Mud spell fix | Trivial | R2.5.4 |
| R2.5.6 | Testing | Low | R2.5.2-R2.5.5 |
