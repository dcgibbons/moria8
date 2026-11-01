# Weapon Exchange (Secondary Weapon Slot) Design

Status: design only, revised 2026-10-31 after the maintainer's decisions and
three reviews ("go with changes"). No product code has been changed. Backlog
entry: `docs/BACKLOG.md` "Add the VMS `x` weapon swap (secondary weapon
slot)"; related entry "Add a cloak equipment slot".

Implemented 2026-10-31 as designed, with these differences found while
implementing:

- C64: `tramp_ego_append_suffix` and `tramp_ego_get_ac_bonus` returned with
  `$01 = BANK_NO_BASIC`, so a call from the Chest overlay (an ego weapon in
  the report or in the new primary) returned into KERNAL ROM and hung (the
  product smoke reproduced it). Both now restore the caller's `$01` and I
  flag (+6 B in C64 `Default`).
- C128's product-path test is a dedicated `C128_TEST_SCRIPTED_EXCHANGE_PRODUCT`
  variant (`exchange_product_smoke128`): the `C128_TEST_SCRIPTED_INPUT` script
  stops at town entry, before any command runs.
- Commodore read side of the save round trip: the save-write smokes load back
  the product-written 33-slot save (C64 slot 2 and Plus/4 with byte checks,
  C128 through the shipping build's title load) instead of a generator
  current-version mode. The generators keep their 31-slot mode.
- The `w` refusal unit tests live in the new `test_item_exchange.s` (with
  the message path linked) rather than `test_item_ui.s`, which stubs the
  combat message buffer. The refusal prints on message row 1, under the
  wear prompt, as take-off's does.

## 0. Decisions (2026-10-31)

| # | Maintainer decision | Where this design applies it |
| --- | --- | --- |
| 1 | Key is SHIFT+X (normalized `$D8`); plain `x` stays Look | §7.1 |
| 2 | Reserve the equipment layout for the future cloak slot now, so the cloak needs no renumbering of the secondary and slot 31 never changes meaning twice. The cloak itself is not implemented here | §3: slot 31 `EQUIP_CLOAK` reserved, slot 32 `EQUIP_SECONDARY`, `TOTAL_INV_SLOTS = 33`. Cost +8 B of arrays per port compared with no reservation; the 8-array walk still works (§3.3). C128 needs a 21-byte relocation (§3.5) |
| 3 | Savings: S2+ (single-block save, one load loop) only. Drop V1 (shared trampoline dispatcher) and V3 (move disarm). Use V3-alt: on C64 the exchange code goes in the Chest overlay; the Items/Help/Chest reload traffic on disk-only machines is an accepted cost | §6, §9. Every other port's Items overlay was re-checked and fits (§8) |
| 4 | Atari: save version moves to `$16`; `$15` saves stay loadable through the existing 31-slot path | §6.2. Verified by assembly: no extra cost. Atari's loader is 5 B smaller than other ports' because its 30-slot branch compiles out |
| 5 | The secondary is not pseudo-ID-sensed (VMS behavior) | `EQUIP_END` stays 31, so `core/turn.s` is unchanged (§5.5) |
| 6 | Fix "`w` replaces a cursed item" in this change (VMS `moria.inc:539-552` refuses) | §4.4, +13 B |
| 7 | Cosmetics use the recommended defaults: label `"Second: "`, help text, no article, no exchange inside the `e`/`i` views or stores | §7.2, §7.3 |
| 8 | Teaching the playtest bot to use X is a follow-up; keep the backlog line | §15 |
| 9 | Player messages must be short: complete within 41 characters where possible, key word first; replace the long VMS cursed message; do not change existing strings | §4.3. All new messages are ≤ 23 characters plus the item name. The cursed refusal reuses the existing 35-character take-off string (0 new bytes) |

Remaining open questions are in §14. There are four, all small.

---

## 1. Measurement baseline (tree state)

Evidence labels:

- **M**: measured from an assembled build of the measured tree.
- **P**: measured from an assembled **prototype** of this design. The
  prototype was applied to a scratch copy of the measured tree, outside the
  repository. It was assembled only and never run.
- **E**: estimate.

Measured tree: `HEAD` `6e75f4e`, plus the uncommitted working tree with
`git diff | sha256sum` = `81bb1a9e…`, copied to scratch at 2026-10-31
21:57 CDT. At that time a concurrent change was editing scroll/potion effect
code (`core/player_item_commands.s` 21:50, `core/spell_effects.s` 21:54,
`core/item_actions_overlay.s` 21:50, `core/scroll_effects_p3.s`,
`core/player_magic_feedback.s`, `core/monster_attack.s`,
`core/monster_magic.s`, new `core/eff_potion_cure.s`). Every number below
moves when that work lands, so re-measure before implementing (Appendix A).

### 1.1 Failures already present in the measured tree (not caused by this design)

Builds were reproduced exactly as the test scripts assemble them (the
`java()` wrappers add `-libdir core`, `common`, `commodore`, `-afo`). The
items marked HEAD-clean assemble at `HEAD`, so the concurrent change
introduced them.

| Failure | Measured | At `HEAD` |
| --- | --- | --- |
| C64 `C64_TEST_SCRIPTED_DETECT_EVIL_PRODUCT` / `…DUNGEON_SPELL` Default overflow | −11 / −10 B | +6 / +7 B (clean) |
| Plus/4 `PLUS4_TEST_SCRIPTED_WAND_SELECTOR_PRODUCT` / `…CHEST_OPEN_PRODUCT` Default overflow | −8 / −4 B | +9 / +13 B (clean) |
| C128 `C128_CACHE_TEST_SKIP_OVERLAY` / `…SKIP_TIER`: `C128ResidentWorld` out of bounds (`$8c5f`/`$8c56` > `$8c4f`) | fail | clean |
| ~60 C128 spell unit tests (`test_bless_prayer128.s` …): unknown symbol `find_random_floor_near` (`core/spell_effects.s:89` now calls the `core/dungeon_features.s:100` helper) | fail | clean |
| `tests/test_timed_buffs.s` is listed in `platforms/commodore/c64/run_tests.sh` but was missing from the snapshot (the concurrent change added it later; not measured) | fail | n/a |
| **C128 `PERF_P1` builds** (all 9 trace variants and `make build128 PERF_P1=1`): `bcs !run_trap_stop+` branch out of range at `core/game_loop.s:2433` (called from `platforms/commodore/c128/main.s:4340`) | fail | **fail** (pre-existing; `PERF_P1=1` is opt-in and not in default `make test128`) |

The earlier draft's "C128 PERF_P1 variant that failed to assemble" was the
`summary` trace variant, which really has no extra defines
(`run_tests128.sh:6181`). It is not a reconstruction error: every `PERF_P1`
build fails the same way at `HEAD`. This design adds 9 B to `game_loop.s`
before line 2433 (`cmd_exchange`), so it does not fix the failure and may
widen the branch distance. It needs a separate follow-up (§14 Q4).

The first four rows must be fixed by the concurrent change before this
feature's gates can pass. They are dependencies, not part of this design.

---

## 2. Upstream Semantics (VMS Moria 4.8 oracle, Umoria for reference)

Sources: VMS Moria at `adce6c8` (verified in
`../moria8-upstream/vms-moria`), Umoria at `2a2a6b7`
(`docs/BEHAVIOR_CHANGE_PROTOCOL.md` "Pinned upstream revisions").

### 2.1 VMS Moria 4.8 (authority)

| Behavior | VMS source |
| --- | --- |
| `inventory[1..inven_max]`, `inven_max = 35`: `1..22` pack, `23` wield, `24..33` other equipment (`32` outer cloak), `34` secondary weapon, `35` scratch | `constants.inc:79`; `variables.inc:166`; `moria.inc:328-344` |
| Key `x`: `reset_flag := true` (free by default), then `inven_command('x')` | `moria.inc:4428-4431` |
| `inven_command 'x'`: if `inventory[23]` or `inventory[34]` is occupied, run `switch_weapon`; otherwise print `"But you are wielding no weapons."` | `moria.inc:699-706` |
| `switch_weapon`: if the primary is cursed, print `"The <name> you are wielding appears to be cursed."` and stop, with no turn taken | `moria.inc:616-626` |
| Otherwise take a turn, swap `[34]`↔`[23]`, run `py_bonuses(-1/+1)`, print `"Primary weapon   : <name>"` if `[23]` is occupied and `"Secondary weapon : <name>"` if `[34]` is occupied | `moria.inc:627-648` |
| `wear`: if the target slot holds a cursed item, print `"The <name> you are wielding/wearing appears to be cursed."` and refuse with no turn | `moria.inc:539-552` |
| Bonus, AC and flag loops cover `23..inven_max-2` (they leave out the secondary) | `moria.inc:165`, `:207`, `:233` |
| The equipment list covers `23..inven_max-1` (it includes the secondary) | `moria.inc:322`, `:343` |
| Taking off the secondary is allowed, with no `py_bonuses` | `moria.inc:389-390` |
| Remove Curse covers the secondary | `magic.inc:61`; `prayer.inc:53` |
| The secondary is saved | `save.inc:242`, `:603` |
| `wear` puts weapons only in slot 23; only `x` fills slot 34 | `moria.inc` `wear` near `:511-520` |

Derived rules:

1. The "no weapons" check comes first, then the curse check on the
   **primary** only. Swapping in a cursed secondary is allowed, and the
   player is then stuck with it.
2. Only a successful swap takes a turn. Both refusals are free.
3. A Primary line prints only if that slot is occupied, and likewise the
   Secondary line.
4. VMS has no pseudo-ID sensing, so the secondary is not sensed
   (decision 5).

### 2.2 Umoria 5.7.15 (not adopted)

Umoria (`ui_inventory.cpp:433-480`) prints only the Primary line and
recomputes heaviness. Moria8 checks weapon weight at attack time
(`core/combat.s`), so it has no heavy state to clear. In the roguelike
keyset `x` is Look and `X` is exchange (`game_run.cpp:1293-1295`), which is
why SHIFT+X is the natural Moria8 key.

---

## 3. Data Layout (with the cloak reservation)

### 3.1 Constants (`core/item_defs.s:24-43`)

```
.const EQUIP_AMULET       = 30                 // unchanged
.const EQUIP_CLOAK        = 31                 // RESERVED: always empty until the cloak slot lands
.const EQUIP_SECONDARY    = 32                 // VMS inventory[34]
.const EQUIP_LAST         = EQUIP_AMULET       // unchanged (becomes EQUIP_CLOAK with the cloak)
.const EQUIP_END          = EQUIP_LAST + 1     // unchanged = 31: AC / pseudo-ID loops
.const VISIBLE_EQUIP_LAST = EQUIP_SECONDARY    // equipment screen + take-off
.const MAX_EQUIP_SLOTS    = TOTAL_INV_SLOTS - MAX_INV_SLOTS   // 11 (was a stale literal 9; no users)
.const TOTAL_INV_SLOTS    = 33
.const LEGACY_INV30_SLOTS = 30                 // replaces LEGACY_TOTAL_INV_SLOTS
.const LEGACY_INV31_SLOTS = 31
```

The 8 parallel arrays (`core/item.s:44-51`, declared in stream order
`inv_item_id, inv_qty, inv_p1, inv_to_hit, inv_to_dam, inv_to_ac,
inv_flags, inv_ego`) each grow from 31 to 33 bytes: **+16 B per port**
(**M**: `inv_ego − inv_item_id` = `7 × 33`).

### 3.2 Why this numbering

Slots 0-30 keep their positions, so `equip_slot_for_cat`, every `EQUIP_*`
user and every test fixture are unchanged. The secondary is placed after the
reserved slot, so the future cloak change is only:

1. `EQUIP_LAST = EQUIP_CLOAK`. `EQUIP_END` becomes 32, so the AC sum
   (`core/player.s:792-811`, `EQUIP_BODY..EQUIP_END-1`) and pseudo-ID
   (`core/turn.s`, `EQUIP_END`) include the cloak and still leave out the
   secondary (32).
2. Remove the one-line reserved-row skip from the equipment screen (§7.2).
3. Item category, `equip_slot_for_cat`, starting kits and the AC test. **No
   save layout change**: every 33-slot save already stores slot 31 (empty),
   so slot 31 goes from "reserved, empty" to "cloak" and never changes
   meaning a second time. The secondary is never renumbered.

Rejected alternatives:

- Secondary at 31 with no reservation (the earlier draft). A cloak at 32
  inside the contiguous AC range would then include the secondary. The cloak
  change would have to renumber the secondary to 31/32 (a second meaning
  change for slot 31) or split the AC loop.
- Taking a pack slot (21) or inserting the cloak among 23-30. Both change the
  meaning of existing saved slots and need a remapping migration.

### 3.3 Cost of the reservation, and the 8-array walk

- **Bytes.** +8 B of arrays per port compared with the unreserved 32-slot
  plan (+16 B compared with today), and +8 B per save stream (inventory
  section 264 B instead of 256).
- **Wrap trick.** It still works, with a generalized condition. Walking the
  8 arrays with one 8-bit index stepping by `TOTAL_INV_SLOTS` and stopping on
  carry takes exactly 8 passes iff `7·T < 256 ≤ 8·T`, that is
  `T ∈ 32..36`. For `T = 33` the offsets are 0, 33, …, 231, and the next add
  (264) sets carry. Indexed absolute addressing (`inv_item_id+22,x`,
  `inv_item_id+32,x`) reaches `+263` without trouble; a page cross only
  costs a cycle. The swap loop uses this form and asserts the condition
  (§4.2).
- **Save loop.** The save loop must also work for `T = 31` in sequencing
  step 1 (§12), so it stops on `cmp #<(8*T) / bne` instead of on carry. That
  costs +2 B and works for every `T` with `7·T < 256` (§6.4).
- **The cheapest safe option is what is specified.** The reservation needs
  one more array slot. No layout reserves a contiguous AC-range index for the
  cloak and keeps the secondary outside that range without it.

### 3.4 Invariants to assert

- In the consumers (`core/item_exchange.s` and `platforms/shared/save.s`),
  not only in `item.s`: `inv_qty == inv_item_id + T`, …,
  `inv_ego == inv_item_id + 7·T` (all 7 offsets: the stream order must match
  the old per-array order), and `7·T < 256`. The swap also asserts
  `8·T ≥ 256`.
- `EQUIP_CLOAK == EQUIP_END` (the reserved slot sits directly after the AC
  range), `EQUIP_SECONDARY == EQUIP_CLOAK + 1 == TOTAL_INV_SLOTS − 1`, and
  `VISIBLE_EQUIP_END == TOTAL_INV_SLOTS`.
- `core/item.s:1887` `"Inventory total slots", TOTAL_INV_SLOTS, 31` → `33`.
  This is the equality check on the constant being changed; nothing is
  weakened. Fix the stale comments at `core/item.s:42` ("30 slots") and
  `core/item.s:452` (`inv_remove_item` "Input: X = slot index (0-29)" →
  `0..TOTAL_INV_SLOTS-1`; equipment slots, including 32, clear in place).

### 3.5 C128 `128.item` relocation (needed only because of the reservation)

`128.item` (`$8c50-$a7ff`, holds the `item.s` arrays at `$91fc`) has
**13 B** free in the product and in every test variant that does not add
hooks (**M**). +16 B would overflow it by 3 B. The prototype hit exactly
this error (**P**: `$8c50-$a802`).

Fix (**P**, assembles clean): move `slain_str` (21 B,
`"You have been slain."`, `platforms/commodore/c128/main.s:3926`) from
`128.item` into the always-resident `128.diskio` payload, next to
`press_key_str` (`main.s:5112-5115`, which already lives there so that
modal code can read it while PLAY or PERSIST owns `$AF00`). The string is
read-only and read only by Bank 0 code (`core/game_loop.s:2675`).

Result: `128.item` 13 → **18 B** free; `128.diskio` 51 → 30 B (worst test
variant 42 → 21 B). This is a C128 ownership change. It needs the
`docs/C128_MEMORY_CONTRACT.md` change record and an assert like the one for
`press_key_str` (`main.s:5454-5455`). It is open question Q1.

---

## 4. Behavior Specification

### 4.1 Command flow

```
key $D8 (SHIFT+X) → petscii_to_command → CMD_EXCHANGE ($1d, was the unused CMD_MAP)
  → command_dispatch_lo/hi[$1d - CMD_STAIRS_DN] → cmd_exchange (core/game_loop.s)
cmd_exchange:                               // 9 B, after cmd_refuel (:2286-2289)
    jsr msg_clear
    jsr tramp_item_exchange                 // per port (§5.4)
    jmp command_result_main_or_status_only  // carry set = turn consumed
```

A successful swap goes through `turn_post_action` like any consumed turn: two
turns in Search mode (TRN-002). A refusal returns carry clear and consumes
nothing. No modal screen is drawn, so the status-only tail is correct.

### 4.2 `item_exchange` (new `core/item_exchange.s`)

It is imported per port into the overlay segment, **not** from
`core/item_actions_overlay.s`, so the 88 C64 unit tests that pull in that
file through `core/player_items.s:450-452` do not grow (§8.4).

```
.assert "Inventory arrays contiguous, stream order", <all 7 offsets>, true
.assert "Swap walk wraps once after 8 arrays", 7*TOTAL_INV_SLOTS < 256 && 8*TOTAL_INV_SLOTS >= 256, true
item_exchange:                              // carry set = turn consumed
    lda inv_item_id + EQUIP_SECONDARY       // corrupt-save guard: the secondary
    cmp #FI_EMPTY                           // may hold only a weapon or nothing
    beq !sec_ok+
    tax
    lda it_category,x
    tax
    lda equip_slot_for_cat,x                // ICAT_WEAPON and ICAT_DIGGING map to EQUIP_WEAPON
    cmp #EQUIP_WEAPON
    bne !none+                              // non-weapon (corrupt save): refuse, `t` recovers it
!sec_ok:
    lda inv_item_id + EQUIP_WEAPON
    and inv_item_id + EQUIP_SECONDARY       // both FI_EMPTY <=> AND == $ff (valid IDs < 140)
    cmp #FI_EMPTY
    bne !have+
!none:
    lda #<ix_no_weapons_str
    ldy #>ix_no_weapons_str
    jsr msg_print_ay
    clc
    rts
!have:
    lda inv_flags + EQUIP_WEAPON            // empty slots hold flags 0 (inv_remove_item)
    and #IF_CURSED
    beq !swap+
    ldx #HSTR_PIW_CURSED                    // existing string, see 4.3
    jmp piw_msg_no_turn                     // prints, carry clear
!swap:
    ldx #0
!loop:                                      // all 8 arrays, stride 33
    lda inv_item_id + EQUIP_WEAPON,x
    ldy inv_item_id + EQUIP_SECONDARY,x
    sta inv_item_id + EQUIP_SECONDARY,x
    tya
    sta inv_item_id + EQUIP_WEAPON,x
    txa
    clc
    adc #TOTAL_INV_SLOTS
    tax
    bcc !loop-
    jsr player_recalc_equipment             // bonus transfer (see notes)
    ldx #EQUIP_WEAPON
    lda #<ix_primary_str
    ldy #>ix_primary_str
    jsr ix_report
    ldx #EQUIP_SECONDARY
    lda #<ix_secondary_str
    ldy #>ix_secondary_str
    jsr ix_report
    sec
    rts
ix_report:                                  // print prefix+description if slot X is occupied
    sta zp_ptr1                             // prefix lo (Y = hi survives)
    lda inv_item_id,x
    cmp #FI_EMPTY
    beq !skip+
    stx piw_slot
    lda #0
    sta cmb_buf_idx
    lda zp_ptr1
    jsr combat_append_str
    ldx piw_slot
    jsr inv_slot_to_fi_add                  // A = item id, fi_add_* staged
    jsr item_append_desc
    jmp cmb_term_and_print
!skip:
    rts
ix_no_weapons_str: .text "No weapons to exchange." ; .byte 0
ix_primary_str:    .text "Primary: " ; .byte 0
ix_secondary_str:  .text "Secondary: " ; .byte 0
```

Size: **176 B** (**P**, all 7 ports; the earlier estimate was 250 B). It
includes the 19-byte corrupt-save guard and 46 B of strings. All callees are
reachable from the routine's overlay on every port (**P** symbol placement):
`player_recalc_equipment` and `piw_msg_no_turn` are resident on
C64/Plus/4/Atari, in the banked runtime on C128 (existing Items-overlay code
already calls `player_recalc_equipment` there, `core/item_actions_overlay.s:179`),
and in the same Items overlay on Apple/CX16/BBC. `item_append_desc` → the
ego suffix path banks in `$F000` on C64 with no overlay load
(`platforms/commodore/c64/main.s:1322-1344`), so it is safe from the Chest
overlay.

Notes:

- **Bonus transfer.** `player_recalc_equipment` rebuilds to-hit, to-dam and AC
  from `EQUIP_WEAPON` and the AC range. Slays, brands, launcher, digging tool
  and blows are read from `EQUIP_WEAPON` at attack time. A secondary's bonuses
  therefore count for nothing, as in VMS `py_bonuses(-1)`.
- **Reserved slot 31** is never touched. A corrupt save that puts an item
  there is harmless: it is outside `EQUIP_END`, not drawn (§7.2), listed by
  take-off, and recovered to the pack by `t`. No load-time guard is added
  (5 B rejected, corrupt saves only).

### 4.3 Messages (decision 9)

| Use | Exact text | Chars | Bytes | Fits 40-col (41) |
| --- | --- | --- | --- | --- |
| Neither slot holds a weapon (or the secondary is corrupt) | `No weapons to exchange.` | 23 | +24 (overlay) | yes, complete |
| Cursed refusal, both X and `w` (§4.4) | `You cannot remove it, it is cursed!` (existing `HSTR_PIW_CURSED`, `data/huffman_strings.txt:130`, already used by take-off) | 35 | **0** | yes, complete |
| After a swap, if the primary is occupied | `Primary: ` + description | 9 + n | +10 | complete when n ≤ 32 |
| After a swap, if the secondary is occupied | `Secondary: ` + description | 11 + n | +12 | complete when n ≤ 30 |

- VMS's `"The <name> you are wielding appears to be cursed."` loses "be
  cursed" on 4 ports. It is replaced by the existing take-off refusal, which
  is accurate for X: the swap would remove the cursed weapon. No existing
  string changes. If the maintainer wants a dedicated X line,
  `Your weapon is cursed!` (22 chars, +23 B in the overlay) is the
  alternative (§14 Q2). `w` keeps the shared string either way, because it
  also refuses cursed armour.
- The Primary/Secondary lines are shorter than the existing
  `You are wielding a ` prefix (19). Long ego names clip on 40-column ports
  (41), C128 (53) and Apple/BBC (63) by the same rule as the existing wield
  message. No article (decision 7).
- The two lines fill message rows 0 and 1 without a `-MORE-`
  (`core/ui_messages.s:106-108`).
- Plain screen-code `.text` strings live in the overlay, the same convention
  as `disarm_no_visible_str` (`core/dungeon_features.s:499-501`). They are
  not Huffman strings, which would be resident data on C64/Plus/4/Atari.

### 4.4 `w` must not replace a cursed item (decision 6)

`core/player_item_commands.s`, `item_wear`, right after
`sta piw_equip` (`:31`):

```
    // VMS wear (moria.inc:539-552): a cursed item in the target slot stays on.
    tax                                     // A = piw_equip
    lda inv_flags,x
    and #IF_CURSED
    beq !iw_not_cursed+
    ldx #HSTR_PIW_CURSED
    jmp piw_msg_no_turn                     // no turn, nothing moved
!iw_not_cursed:
```

The check runs before both the swap path and the stack path (torches), so
neither can displace a cursed item. Empty slots hold flags 0. Cost **+13 B**
(**P**). It lands where `player_item_commands.s` lives: resident `Default`
on C64/Plus/4/Atari, the banked runtime on C128, and the Items overlay on
Apple/CX16/BBC.

---

## 5. Code Sites That Change

### 5.1 Shared constants and data

| Site | Change |
| --- | --- |
| `core/item_defs.s:24-43` | §3.1 constants. `MAX_EQUIP_SLOTS` (`:40`, no users today) becomes derived (11) |
| `core/item.s:42`, `:452`, `:1887` | Comments; assert 31 → 33 |
| `core/input_contract.s:36` | `CMD_MAP = $1d` → `CMD_EXCHANGE = $1d` (unused ID; no other references) |
| `core/input_tables.s:69`, `:98` | `.byte $d8 // SHIFT+X — exchange weapons` after CTRL+W; `CMD_EXCHANGE` after `CMD_WIZARD` (+2 B). Check each port's appended-key count assert (Atari, CX16, C128 append keys) |

### 5.2 Dispatch and handler

| Site | Change |
| --- | --- |
| `core/game_loop.s:1668-1669`, `:1764-1765` | `command_dispatch_lo/hi_map` → `cmd_exchange` (table size unchanged) |
| `core/game_loop.s:1842`, `:1889` | Asserts use `CMD_EXCHANGE` |
| `core/game_loop.s` after `:2289` | `cmd_exchange` (9 B, §4.1) |

### 5.3 Exchange routine placement

| Port | Segment | Import site (after the `item_actions_overlay.s` import, or after `chest.s` on C64) |
| --- | --- | --- |
| C64 | **Chest overlay** (V3-alt, decision 3) | `platforms/commodore/c64/main.s:2913` |
| Plus/4 | Items overlay | `platforms/commodore/plus4/main.s:2386` |
| C128 | Items overlay | `platforms/commodore/c128/main.s:5698` |
| Apple IIe | Items overlay | `platforms/apple2/main.s:1486` |
| CX16 | Items overlay | `platforms/cx16/main.s:1213` |
| Atari 8-bit | Items overlay | `platforms/atari8/main.s:1271` |
| BBC Master | Items overlay | `platforms/bbcmaster/main.s:1301` |

### 5.4 Trampolines (`tramp_item_exchange`)

| Port | Shape | Cost (**P**) |
| --- | --- | --- |
| C64 | `lda #<item_exchange / ldy #>item_exchange / jsr chest_dispatch / jmp tramp_sr_epilogue`. This reuses the existing SMC chest dispatcher (`platforms/commodore/c64/main.s:1691-1700`). A failed load returns carry set (turn consumed), the same as the existing Items trampolines | 10 B |
| Plus/4, Atari | The existing 13-byte `OVL_ITEMS` shape (`plus4/main.s:1603`, `atari8/main.s:809`) | 13 B |
| Apple, CX16, BBC | `lda/ldy/jmp tramp_items_dispatch` (`apple2/main.s:624`, `cx16/main.s:556`, `bbcmaster/main.s:566`) | 7 B |
| C128 | `:C128OverlayComputeTrampoline(C128_ITEMS_OVERLAY_ID, item_exchange)` (`c128/main.s:1562`) | 35 B |

### 5.5 Loops and bounds (constant-driven; no code edits unless noted)

| Site | Bound | Slot 31 (reserved) / slot 32 (secondary) |
| --- | --- | --- |
| `core/player.s:792-811` AC sum | `EQUIP_END` (31) | excluded / excluded (VMS) |
| `core/player_recalc_equipment.s`, `core/player.s:349-437` | fixed slots | excluded / excluded |
| `core/turn.s` pseudo-ID equipment scan | `EQUIP_END` | excluded / **excluded (decision 5)** |
| `core/spell_effects.s:288`, `core/player_magic_execute_overlay.s:381` Remove Curse | `TOTAL_INV_SLOTS` | harmless (flags 0) / **included** (VMS) |
| `core/player_items.s:358-377` take-off cache | `VISIBLE_EQUIP_END` (33), non-empty only | never listed (empty) / listed last |
| `core/ui_equipment.s:59-67` screen | `VISIBLE_EQUIP_SLOTS` (11) | row skipped (§7.2) / row 11 |
| `core/item.s:171-177`, `core/wizard.s:383`, `core/ui_wizard.s:267`, platform init loops (`c64/main.s:2710-2717`, `apple2/main.s:1372-1379`, `cx16/main.s:1117-1124`, `bbcmaster/main.s:1200-1207`) | `TOTAL_INV_SLOTS-1` | cleared / cleared |
| `platforms/shared/save.s` `save_sanitize_id_table` | `TOTAL_INV_SLOTS` | sanitized / sanitized |
| `core/dungeon_features.s` spikes, `core/monster_acid.s`, Items-overlay light/armour code | fixed slots | unaffected |

No `#31`/`#30`/`#$1f` literal indexes the inventory (the earlier audit still
holds). No weight/encumbrance loop exists.

### 5.6 Equipment screen and help

| Site | Change | Cost (**P**) |
| --- | --- | --- |
| `core/ui_equipment.s:59-67` | At `!ueq_cont`: `cmp #EQUIP_CLOAK-EQUIP_WEAPON / bne !shown+ / jmp !ueq_next+`. A plain `beq` is out of range on 40-col (**P**: distance 129) | 7 B |
| `core/ui_equipment.s:189-208` | `ueq_lbl_second: .text "Second: "`, plus two pointer pairs (row 10 reserved points at the same label; never drawn). The assert at `:208` then covers 11 | 13 B |
| `core/ui_help_page2_data.s:82-89` (C64/Plus/4/Atari) | Row 11 right column: `$fc,20,$fe,"SHIFT+X",$ff," Exchange"` | 20 B |
| `platforms/commodore/c128/ui_help_data_80.s:123-125` (C128/Apple/CX16/BBC) | Q row right column: `"SHIFT+X" " Exchange Weapons"` | 28 B |

### 5.7 Save and load

See §6. Files: `platforms/shared/save.s` (`:28`, `:315-343`, `:416-445`,
`:686-696`, `:985-995`, `:1500-1537`). Each port's `hal/storage_policy.s`
gets `hal_storage_save_inv33_version` and a bumped
`hal_storage_save_version`. Also change the Atari policy comment
(`platforms/atari8/hal/storage_policy.s:1-6`).

### 5.8 Tests, harnesses and tools that must change

These edits are part of this change and need maintainer authorization as
test/infrastructure edits under `AGENTS.md` rule 5. S2+ and the new layout
force them; they do not weaken anything.

| Site | Change |
| --- | --- |
| `platforms/commodore/c64/run_tests.sh:4349` (`save_split_item_stats_contract`) | The static text check names `save_block_table_inventory_current:`, `…legacy:` and `:save_block_desc(inv_p1, LEGACY_TOTAL_INV_SLOTS)`. Replace those needles with the single `:save_block_desc(inv_item_id, 8 * TOTAL_INV_SLOTS)` descriptor and the `load_read_inventory_state` loop markers. Keep the store/floor needles |
| `platforms/commodore/c64/tests/test_save.s:145-152` | Add `hal_storage_save_inv33_version` (test-local, = its `save_version`) |
| `test_save.s:514`, `:2401` (`jsr save_write_inventory_state`) | `:save_block(inv_item_id, 8 * TOTAL_INV_SLOTS)` |
| `test_save.s:528`, `:2248`, `:2408` (`jsr load_read_inventory_state`) | Unchanged call; the routine survives |
| `test_save.s:539-545` (`test_save_legacy_inventory_state_blocks` uses the removed legacy table) | Write 8 per-array blocks of 30 (and a new 31-slot variant) with `:save_block` |
| `platforms/commodore/c64/tests/test_main_loop.s:183` | Local stub `tramp_item_exchange` that counts calls and returns a test-set carry (`item_exchange` is no longer imported through `player_items.s`) |
| `platforms/commodore/c128/tests/test_main_loop128.s:427-430`, `:702`, `:735-742` | **Stub, not alias.** The earlier draft said both "alias like `tramp_item_refuel`" and "must not import the consumers". The alias needs `item_exchange.s`, whose contiguity asserts fail against this file's own arrays (declared in a different order). Resolution: a local `tramp_item_exchange` stub as on C64. Set the local `TOTAL_INV_SLOTS = 31` to 33 so the fixture matches the product layout. Never import `item_exchange.s` |
| `platforms/atari8/harness_smoke.py:117-118`, `platforms/bbcmaster/harness_smoke.py:106-107` | The fallback `inv_qty = inv_item_id + 0x20` is stale already (stride 31); make it +`0x21`, or drop the fallback and require the symbol |
| Load-resume generators `c64/tests/make_load_resume_save64.py`, `plus4/tests/make_load_resume_save_plus4.py`, `c128/tests/make_load_resume_save.py` | Keep the 31-slot mode (it now covers the legacy-31 loader). Add a current-version mode (33 slots, slot 32 populated) for the round trip in §11.3 |
| `playtest/moria_playtest/disk.py:360-362` | No change: it derives the inventory span from `inv_item_id`/`inv_flags`/`inv_ego` symbols |

### 5.9 Documentation

| Site | Correction |
| --- | --- |
| `docs/FEATURE_MAP.md:834` (slot layout) | VMS column: 1-based `inven_max = 35` list (`32` outer cloak, `34` secondary, `35` scratch); today it gives Umoria's 0-based list under the VMS heading. Moria8 column: delete the nonexistent `player_aux_slot`; add `31 EQUIP_CLOAK` (reserved, empty) and `32 EQUIP_SECONDARY`; `TOTAL_INV_SLOTS = 33`, `8 × 33 = 264` B; citation `core/item_defs.s:24-43` |
| `docs/FEATURE_MAP.md:93`, `:266` | Equipment slots: 9 active + reserved cloak + secondary, `MAX_EQUIP_SLOTS = 11`, `TOTAL_INV_SLOTS = 33` |
| `docs/FEATURE_MAP.md:387` | VMS: `x` swaps with secondary slot `inventory[34]`. Moria8: SHIFT+X `CMD_EXCHANGE`, `Implemented` |
| `docs/FEATURE_MAP.md:334` | Pseudo-ID stays `22..30`; note that the secondary is deliberately not sensed (VMS) |
| `docs/FEATURE_MAP.md:808` | `TOTAL_INV_SLOTS = 31` → 33 (Remove Curse covers the secondary) |
| `docs/FEATURE_MAP.md` (wear row) | `w` refuses a cursed target slot (VMS) |
| `docs/ATARI8_MEMORY_CONTRACT.md:249`, `docs/ATARI8_PORT_PLAN.md:447` | Derived stream size (§6.5); `OLDEST_SAVE_VERSION` (`$15`) is no longer equal to `SAVE_VERSION` (`$16`) |
| `docs/C128_MEMORY_CONTRACT.md` | `slain_str` ownership in `128.diskio` (§3.5) |
| `docs/BACKLOG.md` | Only if the maintainer says so: the cloak entry can note the reserved slot 31 |

---

## 6. Save Format (S2+)

### 6.1 Today

8 descriptor blocks per array; `≥ SAVE_INV31_VERSION` reads 31 per array,
older versions read 30 (`save.s:323-343`, `:1500-1537`).
`load_read_inventory_state` first runs `item_init_inventory`, so slots the
stream does not cover stay empty.

### 6.2 Versions

| Port | Today `save_version` / `inv31` | New `inv33` = `save_version` |
| --- | --- | --- |
| C64 | `$15` / `$11` | `$16` |
| Plus/4 | `$07` / `$03` | `$08` |
| C128 | `$17` / `$12` | `$18` |
| Apple IIe, CX16, BBC | `$15` / `$11` | `$16` |
| Atari 8-bit | `$15` / `$15` (every constant pinned to `$15`) | `$16`; every other Atari constant stays `$15`. `OLDEST = $15`, so `$15` saves load through the 31-slot path |

**Atari (decision 4, verified by assembly, P).** The version range check
(`save.s:2137-2139`) accepts `$15..$16`. Every other feature gate compares
with a constant of `$15`, so it behaves the same for both versions. The load
loop below wraps its 30-slot branch in
`.if (SAVE_INV31_VERSION > OLDEST_SAVE_VERSION)`, which is false on Atari
only. Atari's loader is therefore 5 B smaller than the other ports' (Atari
`Default` −5 B in the prototype). Keeping `$15` costs nothing.

### 6.3 Stream layout

| Save version | Inventory section |
| --- | --- |
| `< INV31` | 8 × 30 = 240 B (slots 30-32 left empty) |
| `INV31 .. INV33-1` | 8 × 31 = 248 B (slots 31-32 left empty) |
| `≥ INV33` | 8 × 33 = 264 B, arrays in declaration order (byte-identical to 8 per-array blocks of 33) |

### 6.4 S2+ implementation

- **Save.** Append `:save_block_desc(inv_item_id, 8 * TOTAL_INV_SLOTS)` as
  the last entry of `save_block_table_pre_inventory`. Delete the current and
  legacy tables (`save.s:323-343`), their count constants and asserts
  (`:417-418`, `:430-431`, `:444-445`), `save_write_inventory_state`
  (`:1507-1513`) and its call (`:696`). `save_write_block` already takes a
  16-bit count.
- **Load.** Read `SAVE_BLOCK_PRE_INVENTORY_COUNT - 1` entries (`:991`), then:

```
load_inv_slots: .byte 0                     // dedicated scratch (no longer borrows save_block_lo)
load_read_inventory_state:
    jsr item_init_inventory
    ldx #TOTAL_INV_SLOTS
    lda load_save_version
    cmp #SAVE_INV33_VERSION
    bcs !n+
    ldx #LEGACY_INV31_SLOTS
.if (SAVE_INV31_VERSION > OLDEST_SAVE_VERSION) {   // false on Atari: compiled out
    cmp #SAVE_INV31_VERSION
    bcs !n+
    dex                                     // 30
}
!n: stx load_inv_slots
    lda #0
    sta save_count_hi
    sta zp_temp2                            // array offset; load_read_block keeps zp_temp2
!loop:                                      // (load_read_block_table relies on it, :1267-1291)
    clc
    adc #<inv_item_id                       // pointer recomputed every pass
    sta zp_ptr0
    lda #>inv_item_id
    adc #0
    sta zp_ptr0_hi
    lda load_inv_slots
    sta save_count_lo
    jsr load_read_block
    lda zp_temp2
    clc
    adc #TOTAL_INV_SLOTS
    sta zp_temp2
    cmp #<(8 * TOTAL_INV_SLOTS)             // exactly 8 passes for any T with 7*T < 256
    bne !loop-                              // (carry exit would fail for T = 31 in step 1)
    ldx #TOTAL_INV_SLOTS
    lda #<inv_item_id
    ldy #>inv_item_id
    jmp save_sanitize_id_table
```

The intermediate offsets `k·T` (k = 1..7) never equal `<(8·T)` for T = 31,
32 or 33. Because the pointer is recomputed each pass, how far the chunked
C128 path (`load_unstage_to_ptr0_c128`) or the Apple/BBC/CX16 routing
advanced it does not matter. The inventory arrays are in main resident RAM
on every port (**M**: Apple `$4969`, CX16 `$4753`, BBC `$5d23`, C128 Bank 0
`$91fc`), so block routing stays on the main path.

Asserts: the inventory descriptor is the last pre-inventory entry; the
arrays are contiguous in stream order (all 7 offsets); `7·T < 256`.

Size: S2+ saves **53 B** with a carry exit (**P**; 58 B on Atari). The `cmp`
exit specified here costs 2 B, so the net saving is **51 B** (56 B on
Atari). This is in whichever segment holds `save.s`: C64/Plus/4/Atari
`Default`, C128 `128.persist`, Apple/CX16/BBC Storage overlay. The earlier
estimate was 52 B.

### 6.5 Capacity

- **Atari `ATARI_SAVE_SERIALIZED_MAX` (`platforms/atari8/memory.s:180`).
  Leave it at 6,616.** Reason: a reproducible derivation gives the real
  stream size, **6,396 B today and 6,412 B after** (+16). The hand constant
  stays a conservative upper bound, and the slot capacity is 56 × 125 =
  7,000 B. Derivation (**M**, assembled into the Atari build as a `.print`
  at the end of `save.s`):

  `SAVE_MAGIC_SIZE + PL_STRUCT_SIZE + 160 + ZP_STATE_SIZE + 1 + ZP_RNG_SIZE`
  (308 incl. pre-inventory) `+ 8·TOTAL_INV_SLOTS` `+ ID_KNOWN_BYTES` (20)
  `+ post-known table` (1,199) `+ door state` (49) `+ 11·MAX_FLOOR_ITEMS`
  (462) `+ RECALL_DATA_SIZE` (260) `+ MAP_SIZE` (3,840) `+ 2` checksum.

  KickAss divides in floating point, so use `floor()` for `ID_KNOWN_BYTES`.
  Replacing the hand value with an assembler-derived accumulator in
  `save_block_desc` is a possible follow-up, not part of this change.
- **BBC:** 64-sector (16,384 B) slots; +16 B is fine.
- Commodore SEQ, ProDOS and CX16 files have no fixed allocation.

### 6.6 Old-save coverage

The three load-resume generators write 31-slot saves (`$11`, `$03`,
`$13`/`$12`). After the bump, the existing load smokes exercise the
legacy-31 loader through the real product path.

---

## 7. UI and Key Binding

### 7.1 Key (decision 1)

SHIFT+X normalizes to `$D8` on every port: native PETSCII on
C64/C128/Plus/4/CX16; `ora #$80` on Apple (`apple2/input.s:223`); the shifted
KBCODE row on Atari (`atari8/input.s:188-189`); uppercase ASCII on BBC
(`bbcmaster/input.s:207-208`). `$D8` is absent from every keymap today.
Plain `x` (`$58`) stays `CMD_LOOK` (`core/input_tables.s:51`). The playtest
driver injects normalized return codes (`playtest/moria_playtest/ports.py`
`key_feed`), and the bot's Look key is `ord("X")` = `$58`
(`brain.py:34`), so the bot is unaffected.

### 7.2 Equipment screen

The 11th row (index 10) is `Second: <item>` (8-character label, aligned).
Row index 9, the reserved cloak, is skipped and stays blank until the cloak
lands; the cloak change then removes the skip. 40-column wrap layout
(C64/Plus/4/Atari, 25 rows): index 10 sits on rows 22-23 and the footer on
row 24 (`SCREEN_ROWS-1`). 80-column ports use rows 2-12. Take-off letters
count only occupied slots in slot order (`ueq_visible`,
`piw_build_visible_equip_cache`), so the letters on the screen and in the
prompt still agree. A compact layout without the blank row needs a separate
row counter (≈ +6 B, **E**); not proposed.

### 7.3 Help

40-col: `SHIFT+X Exchange` in the right column of page 2, row 11. 80-col:
`SHIFT+X Exchange Weapons` beside `Q Quaff Potion`.

---

## 8. Per-Port Placement and Budget

### 8.1 Where each piece lands (**P** symbols)

| Port | arrays (`item.s`) | key map, handler | trampoline | `save.s` | `ui_equipment.s` | help | `item_exchange` | `w` fix (`player_item_commands.s`) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| C64 | Default | Default | Default | Default | Help ovl | Help ovl | **Chest ovl** `$e754` | Default |
| Plus/4 | Default | Default | Default | Default | Help ovl | Help ovl | Items ovl | Default |
| C128 | `128.item` | Default / `128.play` | Default | `128.persist` | Help ovl | Help ovl | Items ovl | banked `$F000` |
| Apple IIe | Resident | Resident / play slot | Resident | Storage ovl | UI ovl | Help ovl | Items ovl | Items ovl |
| CX16 | Resident | Resident | Resident | Storage ovl | Help ovl | Help ovl | Items ovl | Items ovl |
| Atari | Default | Default | Default | Default | Help ovl | Help ovl | Items ovl | Default |
| BBC | Resident | Resident / play slot | Resident | Storage ovl | UI ovl | Help ovl | Items ovl (SWR slot) | Items ovl |

### 8.2 Free bytes: now (**M**) and after (**P**)

"Worst" is the smallest free space among the product build and every test
variant that assembles (Appendix A: 29 C64, 26 Plus/4 and 26 C128 non-PERF
builds, of which 27, 24 and 24 assemble in the measured tree). Square brackets mark variants that already fail in the measured
tree (§1.1). "After" uses the prototype's measured delta, with the S2+
`cmp` exit (+2 B) added to the segment holding `save.s`.

| Port | Segment (limit) | Now: product / worst | Change | After: product / worst |
| --- | --- | --- | --- | --- |
| **C64** | Default (`program_end ≤ $C000`) | 109 / 56 (`SPELL_LIST_OVERLAY`) [−11, −10] | **−1** (+16 arrays +2 key +9 handler +10 tramp +13 `w` −51 S2+) | **110 / 57** [−10, −9] |
| C64 | Items ovl (`≤ $F000`) | 97 / 92 (`SCROLL_SELECTOR`) | 0 | 97 / 92 |
| C64 | Chest ovl | 2,220 / 2,045 (`CHEST_OPEN`) | +176 | 2,044 / 1,869 |
| C64 | Help ovl | 256 / 251 | +40 | 216 / 211 |
| C64 | RuntimeBanked (`≤ $FFFA`) | 62 | 0 | 62 |
| **Plus/4** | Default (`program_end ≤ $C800`) | 49 / 15 (`DISK_SETUP_SINGLE_DRIVE_RETURN`) [−8, −4] | **+2** (+16 +2 +9 +13 tramp +13 −51) | **47 / 13** [−10, −6] |
| Plus/4 | Items ovl | 550 | +176 | 374 |
| Plus/4 | Help ovl | 361 / 356 | +40 | 321 / 316 |
| **C128** | Default (`≤ $6000`) | 489 / 106 (`SCRIPTED_INPUT+CACHE_SURVIVAL`) | +37 (key 2, tramp 35) | 452 / 69 |
| C128 | `128.item` (`≤ $A800`) | 13 / 13 | +16 −21 (`slain_str`, §3.5) | **18 / 18** (−3 without the move) |
| C128 | `128.diskio` (`≤ $AF00`) | 51 / 42 | +21 | 30 / 21 |
| C128 | `128.world` (`≤ $8C50`) | 9 / 6 [2 fail] | 0 | 9 / 6 |
| C128 | `128.play` (`≤ $D000`) | 132 / 114 (`FORCE_DEATH`) | +9 | 123 / 105 |
| C128 | `128.persist` (`≤ $D000`) | 4,955 | −51 | 5,006 |
| C128 | Banked (`≤ $FF00`) | 137 / 119 (`SPELL_CANCEL`) | +13 (`w`) | 124 / 106 |
| C128 | Items ovl (4,096 cache slot) | 428 | +176 | 252 |
| C128 | Help ovl (4,096 cache slot) | 75 / 70 | +48 | 27 / 22 |
| **Apple IIe** | Resident (`≤ $7C00`) | 361 | +25 | 336 |
| Apple | Play slot (`≤ $A000`) | 132 | +9 | 123 |
| Apple | Items ovl (`≤ $BA00`, aux cache slot) | 616 | +189 (+176 +13 `w`) | 427 |
| Apple | UI ovl (2,560) | 1,252 | +20 | 1,232 |
| Apple | Help ovl | 2,259 | +28 | 2,231 |
| Apple | Storage ovl | 373 | −51 | 424 |
| **CX16** | Resident (`≤ $9B00`) | 409 | +34 | 375 |
| CX16 | Items ovl (8 KB bank) | 3,118 | +189 | 2,929 |
| CX16 | Help ovl | 5,982 | +48 | 5,934 |
| CX16 | Storage ovl | 4,818 | −51 | 4,869 |
| **Atari** | Default (`≤ $C100`) | 86 | **−3** (+16 +2 +9 +13 +13 −56) | **89** |
| Atari | Items ovl | 550 | +176 | 374 |
| Atari | Help ovl | 496 | +40 | 456 |
| Atari | RuntimeBanked (`≤ $FFFA`) | 288 | 0 | 288 |
| **BBC** | Resident (`≤ $8000`) | 256 | +25 | 231 |
| BBC | Play slot (`≤ $A400`) | 47 | +9 | 38 |
| BBC | Items ovl (**SWR slot 21 pages = 5,376**) | 360 | +189 | **171** |
| BBC | UI ovl (10 pages) | 1,252 | +20 | 1,232 |
| BBC | Help ovl | 2,771 | +28 | 2,743 |
| BBC | Storage ovl | 2,322 | −51 | 2,373 |

Per-port net, tightest segment: C64 Default +1 B (57 B worst passing);
Plus/4 Default −2 B (13 B worst passing); C128 `128.item` +5 B with the
§3.5 move (18 B), Help 22 B; Apple Items 427 B; CX16 Resident 375 B; Atari
Default +3 B (89 B); BBC play slot 38 B and Items SWR slot 171 B. Every
segment fits on every port. The bracketed failures already exist in the
measured tree; this feature makes the C64 ones 1 B better and the Plus/4
ones 2 B worse (§14 Q3).

Without V3-alt, C64's Items overlay would be 97 − 176 = −79 B (−84 worst):
confirmed. On every other port the Items overlay has room, so the exchange
stays there.

### 8.3 Measured against the earlier estimates

| Item | Earlier (**E**) | Now | Why |
| --- | --- | --- | --- |
| `item_exchange` | ≈ 250 | **176 (P)** | Cursed refusal reuses `HSTR_PIW_CURSED`; short messages; +19 B corrupt guard |
| Arrays | +8 | **+16 (M)** | Cloak reservation (33 slots) |
| C64 trampoline | 13 (7 with V1) | **10 (P)** | `chest_dispatch` reuse; V1 dropped |
| S2+ | −52 | **−51 (P)** (−56 Atari) | Measured −53 with carry exit, +2 for the `cmp` exit |
| `ui_equipment.s` | 11 | **20 (P)** | Reserved-row skip and an 11th pointer pair |
| Help | 20 / 28 | **20 / 28 (P)** | as estimated |
| `w` fix | not in scope | **+13 (P)** | Decision 6 |
| C128 `128.item` | 5 left | **18 left (P)**, −3 without §3.5 | Reservation plus `slain_str` move |

### 8.4 Unit-test build fallout (**P**)

- C64: all 110 unit tests in `run_tests.sh` were assembled against the
  prototype. Images grow 31-51 B (arrays, `w`, `ui_equipment`). The largest
  image (`test_ranged`) ends at `$CE77` (was `$CE44`), 393 B below `$D000`.
  Bootstrap/`test_start` placement is unchanged: the four tests without a
  bootstrap start at or below `$1B4E`, far below the `$A000` limit. Only two
  tests break, both by planned edits: `test_main_loop` (needs the
  `tramp_item_exchange` stub) and `test_save` (needs the new version
  constant and the S2+ edits, §5.8). Because `item_exchange.s` stays out of
  the `player_items.s` → `item_actions_overlay.s` import chain, the 176 B
  routine adds nothing to the 88 tests that import `player_items.s`.
- C128: of 80 unit tests, only `test_main_loop128` newly fails (stub,
  §5.8). The ~60 spell tests fail before and after (§1.1).

---

## 9. Savings and Ownership (decision 3)

| ID | Status | What |
| --- | --- | --- |
| **S2+** | **Adopted** | Single 264-byte inventory descriptor in the pre-inventory table, one per-array load loop with a dedicated `load_inv_slots` byte (§6.4). −51 B (−56 Atari) |
| **V3-alt** | **Adopted (C64 only)** | `item_exchange` in the C64 Chest overlay through `chest_dispatch`. **Accepted cost:** on a C64 without an REU (the Chest overlay is REU-stashed when an REU is present), alternating SHIFT+X with any Items-overlay command (read, aim, use, fire, throw, refuel, bash, disarm, tunnel, jam) or with Help reloads an overlay from disk on every switch. With an REU the reload is a stash copy. `w`, `t`, `e`, `i` are resident and do not trigger it |
| V1 | Dropped | Shared SMC trampoline dispatcher |
| V3 | Dropped | Moving `disarm.s` + `disarm_helpers.s` |
| C128 L1 | Needed (Q1) | `slain_str` → `128.diskio` (§3.5) |

Not used: shortening any existing string, loosening any assert, or moving the
new strings into the Huffman corpus (resident data on C64/Plus/4/Atari).

---

## 10. Risks

| ID | Risk | Mitigation |
| --- | --- | --- |
| R1 | The concurrent effect-code change keeps moving C64/Plus/4/Atari `Default`, C128 world/banked and the Items overlays; it already breaks variants (§1.1) | Re-measure after it lands (Appendix A). This feature is −1 / +2 / −3 B on C64 / Plus/4 / Atari `Default` |
| R2 | C128 `128.item` has 18 B left only with §3.5 | Assert; the relocation is a C128 change record |
| R3 | BBC Items SWR slot 171 B, BBC play slot 38 B | Existing asserts (`bbcmaster/main.s:1440`, `:1618`) fail safely |
| R4 | Swap and S2+ depend on array contiguity and order | Asserts in both consumers (§3.4); `test_main_loop128` uses a stub, never the consumers |
| R5 | V3-alt overlay reloads on disk-only C64 | Accepted (decision 3) |
| R6 | A corrupt secondary (non-weapon) | Refused by X, no turn; `t` recovers it (§4.2) |
| R7 | Atari `$15` saves | Load through the 31-slot path (§6.2); covered by the static assert in §11.3 |
| R8 | Long ego names clip on the Primary/Secondary lines | Same rule as the existing wield message, with a shorter prefix (§4.3) |
| R9 | `PERF_P1` C128 builds already fail; `cmd_exchange` adds 9 B ahead of `game_loop.s:2433` | Separate follow-up (Q4) |
| R10 | The reserved row leaves a blank line on the equipment screen until the cloak exists | Cosmetic; the cloak change removes the skip |

---

## 11. Test Plan

Oracle: the VMS lines in §2.1. **All expected values are written by hand in
the test files.** Message checks compare the printed message row (screen
RAM or `msg_history`) against literal `.text` bytes in the test. They never
compare against the product's own labels (`ix_no_weapons_str`,
`HSTR_PIW_CURSED`), which would be tautological. Stat checks compare against
numbers computed by hand from the fixture.

### 11.1 Unit: new `platforms/commodore/c64/tests/test_item_exchange.s`

It imports the real `core/item.s`, `player_items.s`, `player_item_commands.s`,
`player_recalc_equipment.s`, the message path, and `core/item_exchange.s`
explicitly. Fixture: a fixed `player_data` with known base to-hit/to-dam/AC.

1. **Empty:** both slots empty → carry clear; all 8 arrays at slots 22, 31
   and 32 unchanged; message row = literal `"No weapons to exchange."`.
2. **Cursed primary:** primary `IF_CURSED`, secondary present → carry clear;
   both 8-field records byte-identical; `PL_TOHIT`/`PL_TODMG`/`PL_AC`
   unchanged; message = literal `"You cannot remove it, it is cursed!"`.
3. **Bonus transfer:** primary Dagger (+3,+4) Defender, secondary plain
   (+1,+0) → carry set; records exchanged in all 8 arrays; `PL_TOHIT` =
   base+1, `PL_TODMG` = base+0, `PL_AC` = armour only (Defender bonus gone).
   Numbers are literal.
4. **Primary only** → it moves to slot 32; to-hit/to-dam drop to base; only
   the literal `"Secondary: <desc>"` line prints.
5. **Secondary only** → it moves to slot 22; only `"Primary: <desc>"`.
6. **Cursed secondary** → the swap is allowed; a second X is refused (2).
7. **Involution:** X twice restores the records and the derived stats.
8. **Exclusion/inclusion:** a secondary with nonzero `inv_to_ac` and an ego
   leaves `PL_AC`, `player_pflags` and slaying unchanged; `eff_remove_curse`
   and `eff_remove_curse_all` clear its `IF_CURSED`; the pseudo-ID scan
   (`core/turn.s`) never selects slot 32.
9. **Corrupt secondary:** a non-weapon ID in slot 32 → carry clear, no
   change, "No weapons" literal; `item_takeoff` then moves it to the pack.
10. **Reserved slot:** slot 31 stays `FI_EMPTY` with zero fields through 1-9;
    `piw_build_visible_equip_cache` lists slot 32 last and never slot 31.

### 11.2 Unit: `w` cursed refusal (`platforms/commodore/c64/tests/test_item_ui.s`, next to `:488`/`:860`)

- Cursed weapon wielded, `w` another weapon → carry clear, both records
  unchanged, literal message, no turn.
- Cursed body armour, `w` armour → refused the same way.
- Cursed torch in the light slot, `w` a torch from a stack → refused (stack
  path).
- Uncursed target → today's swap behavior (regression).

### 11.3 Save and load

- **Unit (`test_save.s`):** round trip with slot 32 populated and slot 31
  empty: all 264 bytes restored, inventory section exactly 264 B; legacy-31
  stream → slots 0-30 restored, 31/32 empty, next block aligned (check a
  sentinel in the known-items block); legacy-30 stream likewise; the version
  gate accepts `INV33` and rejects `INV33+1`; **step 1 (T = 31) stream is
  byte-identical** to the old 8-block writer.
- **Atari static:** assert `SAVE_INV31_VERSION == OLDEST_SAVE_VERSION`,
  `SAVE_INV33_VERSION == SAVE_VERSION == OLDEST_SAVE_VERSION + 1` in the
  Atari build.
- **Product round trip on every port**, populated secondary (slot 32 =
  a known weapon record, slot 31 empty):

| Port | Write side | Read side |
| --- | --- | --- |
| C64 | `run_save_write_product_smoke` (`C64_TEST_SCRIPTED_SAVE_WRITE_PRODUCT`): seed slot 32 before the scripted save, then extract the SEQ and compare the 264-byte inventory section host-side | `run_load_resume_product_smoke` with the generator's new current-version mode; check `inv_*` at 31/32 via monitor |
| Plus/4 | `run_save_write_product_smoke` (`PLUS4_TEST_SCRIPTED_SAVE_WRITE_PRODUCT`), same check | `run_load_resume_product_smoke`, current-version generator mode |
| C128 (chunked) | `boot_title_save_write_product_smoke` (`C128_TEST_SCRIPTED_SAVE_WRITE_PRODUCT`), same host-side check: this covers `c128_save_stream_chunk` with a 264-byte block | `boot_title_load_mounted_save_smoke`, current-version mode of `make_load_resume_save.py`: covers `c128_load_stream_chunk` |
| Apple IIe | `save_reboot_load` session A seeds slot 32 before saving | session B (cold boot) checks slot 32/31 |
| CX16 | `save_load`: seed before save | same scenario, check after load |
| Atari | `save_load` and `save_load_130xe`: seed before save | `save_load_resumed` check |
| BBC | `save_load`: seed before save | `save_load_resumed` check |

The existing 31-slot generators keep covering the legacy-31 path through
the real loaders (§6.6).

### 11.4 SHIFT+X product path on every port

Each test seeds weapons in slots 22/32, injects `$D8`, and asserts: records
swapped, turn counter +1, message row text (literal), and with a cursed
primary a refusal with no turn.

| Port | Test |
| --- | --- |
| C64 | New `C64_TEST_SCRIPTED_EXCHANGE_PRODUCT` / `run_exchange_product_smoke`. It must load the **Chest** overlay from disk (no REU) and return to the main loop with `OVL` state intact. A new define variant is its own build; its hooks must fit the 110 B product headroom |
| Plus/4 | New `PLUS4_TEST_SCRIPTED_EXCHANGE_PRODUCT` (hooks must fit 47 B) |
| C128 | Add SHIFT+X to the `C128_TEST_SCRIPTED_INPUT` key script (Default 506 B, `128.play` 404 B in that variant) |
| Apple, CX16 | New `weapon_exchange` harness scenario |
| Atari, BBC | Extend `item_actions` (or a new `weapon_exchange` scenario). Confirm that the injected key reaches `input_get_key` as `$D8` |

Dispatch and turn accounting (`test_main_loop.s`, `test_main_loop128.s`
with the stub): `$D8` → `CMD_EXCHANGE`; stub carry set → one turn (two in
Search mode, TRN-002); carry clear → none; `$58` is still Look. Keymap
parity: `petscii_to_command($D8) == CMD_EXCHANGE` on every port, including
the appended-key count asserts.

Equipment screen: 40-column rows 22/23 hold the secondary, row 20/21 blank,
footer intact on row 24; 80-column row 12.

### 11.5 Gates

Focused first: `make test64 TEST_FILTER=…` (`item_exchange`, `item_ui`,
`save`, `main_loop`), `make test128-fast`, the new product smokes. Then:
`make build`, `make check128-payloads`, `make test64`, `make testplus4`,
`make test128` (full: `128.item`, `128.diskio`, `128.persist` and the
Items/Help caches change), `make testapple2-runtime`, `make testcx16`,
`make testatari8`, `make testbbcmaster`, `make playtest-smoke`, and finally
`make test`. Shared `core/` and `platforms/shared/` changes require every
shipping platform (`docs/INTERNAL_MANDATES.md` "Shared Code").

---

## 12. Sequencing

1. **S2+ alone, as its own gated change, with its test edits.** `T` stays 31
   and the version is **not** bumped. Proof obligation: the save stream is
   byte-identical (unit test in §11.3). Edits: `save.s` (§6.4, `cmp` exit so
   that T = 31 works), `run_tests.sh:4349`, `test_save.s` (§5.8; authorized
   test edits). Gates: `make test64` (save), `make test128` (chunked
   save/load), `make testplus4`, the four MAME/x16 `save_load` runs, then
   `make test`.
2. **The feature on all 7 ports in one change.** Layout (§3), versions,
   `cmd_exchange`, trampolines, `item_exchange`, the `w` fix, the screen,
   help, the C128 §3.5 move, tests (§11), docs (§5.9). Run the focused tests
   first.
3. **Full gate (`make test`) last.** If the maintainer wants a playtest round
   after step 2, it runs after the focused tests and before the full gates,
   never overlapping them. The bot does not press X and no RNG draw changes
   (pseudo-ID untouched), so outcomes should differ only through the save
   format. No frozen-suite regression run unless asked.

Prerequisite for any gate: the §1.1 failures from the concurrent change are
fixed.

---

## 13. Protocol Record (draft for implementation)

Tier: **Architectural** (memory layout, save format, C64 overlay ownership,
C128 payload ownership). Contracts: `docs/BEHAVIOR_CHANGE_PROTOCOL.md`;
`docs/TURN_RENDER_CONTRACT.md` (new turn-consuming command on the existing
status-only tail); `docs/C128_MEMORY_CONTRACT.md` (`128.item` +16, `slain_str`
→ `128.diskio`, Items/Help cache growth); `docs/APPLE2_MEMORY_POLICY.md`;
`docs/CX16_MEMORY_CONTRACT.md`; `docs/ATARI8_MEMORY_CONTRACT.md` (save
size/version policy); `docs/BBCMASTER_MEMORY_CONTRACT.md` (Items SWR slot).
`docs/MONSTER_STATE_CONTRACT.md` and `docs/DUNGEON_GENERATION_CONTRACT.md`
are N/A (no monster or generation state).

```text
Problem and success criteria: VMS x exchange (2.1) on all 7 ports via SHIFT+X; w refuses cursed targets; old saves load; 11.1-11.4 pass.
State being changed: inv_* arrays (33 slots: 31 reserved, 32 secondary); save inventory section (264 B); CMD id $1d; keymap; equipment rows; C128 slain_str ownership.
Search scope and terms: TOTAL_INV_SLOTS, EQUIP_*, VISIBLE_EQUIP*, MAX_EQUIP_SLOTS, LEGACY_TOTAL_INV_SLOTS, literal #22/#30/#31/#$1f, CMD_MAP, $d8, save_block_table_inventory*, save_write_inventory_state (5, 5.8).
Readers/writers and exclusions: 5.5.
Initialization, reset, persistence: item_init_inventory; load_read_inventory_state; inv_remove_item clears fields; save_sanitize_id_table.
Production sequence: key → petscii_to_command → command_dispatch → cmd_exchange → tramp (C64: chest_dispatch) → item_exchange → player_recalc_equipment → command_result_main_or_status_only → turn_post_action.
Upstream oracle: VMS moria.inc:539-552, :616-648, :699-706, :4428-4431.
Intentional deviations: SHIFT+X key; short messages (4.3), cursed refusal reuses HSTR_PIW_CURSED; no article; no x in e/i views or stores; corrupt secondary refused.
Widths/overflow: 8-bit array offsets, 7*T < 256 asserted; swap wraps on carry (T in 32..36 asserted); load loop exits on cmp #<(8*T).
RNG: none (pseudo-ID unchanged).
Platforms/overlays/owners: 8.1; C64 Chest overlay; C128 128.diskio.
Required production-path tests: 11.3, 11.4.
Out of scope: playtest bot use of X; cloak slot itself; PERF_P1 build failure.
Unresolved: section 14.
```

---

## 14. Open Questions for the Maintainer

**Answered 2026-10-31:** (1) move C128 `slain_str` to `128.diskio`: yes;
(2) reuse "You cannot remove it, it is cursed!" for X and `w`: yes; (3) accept
Plus/4's +2 B resident cost (exchange stays in its Items overlay): yes;
(4) the `PERF_P1` failure goes to docs/BACKLOG.md: done. The questions below
are kept for the record.


1. **C128 `128.item`.** Approve moving `slain_str` (21 B) to the
   always-resident `128.diskio` (§3.5)? Without that move, or another
   ≥ 3-byte move out of `128.item`, the cloak reservation does not fit on
   C128.
2. **Cursed refusal text for X.** Reuse the existing
   `You cannot remove it, it is cursed!` (35 chars, 0 B; recommended), or a
   dedicated `Your weapon is cursed!` (22 chars, +23 B overlay)? `w` uses the
   existing string either way.
3. **Plus/4 resident +2 B.** Accept it (Items overlay placement,
   recommended), or put the Plus/4 exchange in the Chest overlay through
   `chest_dispatch` (−3 B, with the same reload cost as C64 on a disk-only
   machine)?
4. **Pre-existing `PERF_P1` C128 build failure** (`core/game_loop.s:2433`
   branch range, fails at `HEAD`). Backlog it or fix it separately? It is
   opt-in and outside the default gates, and this feature leaves it as is.

---

## 15. Follow-ups (not in this change)

- Teach the playtest bot to use SHIFT+X (decision 8; keep the backlog line).
  Optionally add `$D8` to `playtest/moria_playtest/fuzz.py`'s key list.
- The cloak slot (`docs/BACKLOG.md`): §3.2 lists the three edits it then
  needs; no save migration.
- Replace `ATARI_SAVE_SERIALIZED_MAX` with an assembler-derived stream size
  (§6.5).
- `PERF_P1` build failure (Q4).

---

## Appendix A. Measurement Method

- The measured tree (§1) was copied to a scratch directory outside the
  repository. Nothing was written to `build/` or source directories; no
  emulator was launched. `build/version_strings.inc` was only read.
- Product builds: each port's `main.s` assembled with
  `tools/kickass/KickAss.jar` and the platform Makefile flags. Commodore
  test variants were assembled exactly as the test scripts do, including the
  `java()` wrapper flags (`-libdir core -libdir platforms/commodore/common
  -libdir platforms/commodore -afo`).
- Variant sets were extracted from `c64/run_tests.sh` (every
  `-define C64_TEST_SCRIPTED_*`, including the `$test_define` callers),
  `plus4/run_testsplus4.sh` (`KA_FLAGSPLUS4` strings) and
  `c128/run_tests128.sh`. For C128 the `PERF_P1` trace variants were
  resolved through their callers (`run_tests128.sh:6152-6200`). Apple, CX16,
  Atari and BBC test with the product build.
- Free space = segment limit − (end + 1), taken from the `-showmem` map and
  the `program_end` / `a2_play_end` / `beeb_play_end` symbols. Limits come
  from the asserts and `.segmentdef`s cited in §8.2.
- The prototype applied §3-§7 to a second scratch copy and was assembled
  for all 7 products, all variants, 110 C64 unit tests and 80 C128 unit
  tests. Its numbers are byte counts, not behavior.
- To re-measure after the concurrent change lands: repeat the product and
  variant builds on the new tree, then apply the §8.2 deltas, which do not
  depend on the concurrent edits.
