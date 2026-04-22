# Moria C64/C128 — Active Build Plan

> Active outstanding work only.
> See [DESIGN.md](DESIGN.md) for architecture reference and [BUILDPLAN_HISTORY.md](BUILDPLAN_HISTORY.md) for completed phases, fixes, and reviews.

---

## Current State (2026-04-13)

- All core phases 1–9 are complete.
- C128 split, extended-memory database path, larger dungeon, hardened execution boundary, and the current 80-column baseline are complete.
- The Commodore build is centered on [Makefile](Makefile), with the root [Makefile](../Makefile) acting as a thin wrapper.
- Shipping disk artifacts are now split by platform:
  - C64: [out/moria8-c64.d64](out/moria8-c64.d64)
  - C128: [out/moria8-c128.d71](out/moria8-c128.d71)
- C64 now has a working boot-art path that loads a separate `bootart64` asset, copies it into a VIC-safe hidden-RAM bitmap layout, keeps it visible through the later `MORIA64` load, and is now sourced from the tracked artist PNG at `artwork/moria8_loading_art_c64.png`.
- C128 now has a working native 80-column boot-art path that loads a generated VDC custom-charset poster helper, keeps it visible through the later `MORIA128` load, then restores the normal charset contract before the title flow.
- The C128 boot-art helper now writes the poster attribute map before the screen map, so the custom-font poster does not flash briefly under the old charset state first.
- The help/modal cancel contract is now platform-correct:
  - C64 uses `RUN/STOP` as the escape-equivalent dismiss key for help and other read-only modal screens
  - C128 keeps real `ESC` support and also accepts `STOP` so modal dismissal remains reliable under VICE host-key mapping quirks
  - the shared modal input helper layer now owns that escape-equivalent classification instead of open-coded raw key compares
- The current shipping-art baseline is split by platform:
  - C64 uses the shipped artist PNG through the bitmap boot-art pipeline.
  - C128 still uses the generated fallback `MORIA8` VDC poster helper.
- The title screen and disk directory cards now show per-platform display versions sourced from [../version.json](../version.json).
- Town now uses a fixed shared `66x22` footprint on both platforms, with the 8-building Commodore layout refit inside that space; C64 clamps town viewport movement to that logical footprint, while C128 preserves the existing wide entry framing and prevents fake border-wall artifacts by keeping out-of-town backing space non-presentational.
- FEAT-DISK is now operational on both platforms:
  - C64 title `L`, one-drive/two-drive setup, save-disk marker init, save, and load are working again.
  - C128 in-game `Shift+S`, save-disk marker init on drive `9`, save, reboot, and later load are working again.
- The shared save/load refactor is now closed on both platforms:
  - save files are kept after load and after death instead of being consumed automatically
  - saving over an existing `THE.GAME` now asks for overwrite confirmation
  - C128 one-drive flows no longer ask for the program disk again after initial load
  - C64/C128 prompt cadence and fullscreen clears have been reworked so save/load disk prompts no longer stack on stale gameplay/title screens
- Post-refactor copy audit follow-up is now closed:
  - the restored pre-refactor save/load runtime strings remain in place
  - the C64 resident overrun was fixed by moving the dead save-side RLE compressor to test-only ownership instead of touching user-facing copy
  - the follow-up C64 UI ownership pass is also now closed:
    - `UiOverlay` now owns the character and equipment modal screens on C64
    - inventory is back on the banked C64 path because it is a high-frequency command and the measured cost is only `240` bytes
    - monster recall and wizard stay on the banked C64 path because both can hit gameplay/tier restore flows that need the live `$E000` tier window
    - the dead resident `string_bank.s` import and dead banked `string_bank_banked.s` import are both gone from the shipping C64 image
    - current direct C64 assembly reports `Program fits below MAP_BASE=true` with `banked payload: 2898 bytes at $BE6E-$C9C0`
- The recent C128 `Glyph of Warding` cast-text corruption is now closed:
  - the root cause was ownership/layout drift, not character encoding
  - gameplay spell text no longer depends on raw resident literals that can spill into `DeathOverlay` or past the C128 staged-source ceiling
  - the glyph feedback and save/load status copy now live in the shared Huffman dictionary, which restored the C128 staged image under `$E000` without shortening user-facing text
- The recent C128 `Glyph of Warding` disappearing-glyph redraw bug is now closed:
  - the root cause was renderer parity drift, not lost glyph state
  - full `render_viewport` now reapplies the glyph overlay instead of only the single-tile path doing so
  - the focused VDC renderer tests now cover glyph overlay on full redraw so room-reveal redraws cannot silently erase visible glyphs again
- The mixed spell/prayer book inventory prompt bug is now closed:
  - upstream `umoria` and `vms-moria` filter book prompts by exact book class before selection, while the Commodore port had drifted to a broad `ICAT_BOOK` prompt followed by late rejection
  - the live fix now uses exact mage-book vs prayer-book prompt filters, so both the visible letters and the `?` inventory overlay only show books the active caster can actually use
  - the focused regression coverage now seeds a mixed inventory and asserts that prayer selection only renders prayer books in the visible prompt list
- The `drop` item prompt contract is now back in line with the rest of the item selectors:
  - sparse all-item inventories once again advertise the real highest selectable letter instead of a hardcoded `(a-v)` range
  - the C128 live fix also handles lowercase direct-scan letter picks on the `drop -> ?` path without widening the shared prompt parser contract
  - the final fix stayed local enough to keep the C128 staged-source/build128 gate green instead of growing the shared prompt machinery
- Carried inventory removal now matches upstream Moria pack compaction:
  - local `umoria` and `vms-moria` both shift later carried items left after a whole-item removal, and the Commodore port now does the same instead of preserving sparse holes
  - carried-item letters now follow the current packed order, while equipment remains fixed-slot
  - the exact verification gates are back at the intended state after the change: forced `build128` is green again and the C64 full test command is restored to its prior `41 passed, 4 failed` baseline
- `FEAT-VMS-RECALL-SEMANTICS` is now closed:
  - `/` now uses VMS-style symbol identification instead of combat-earned monster recall
  - the glossary lives in `OVL.UI` so the feature fits the C64 resident layout without reopening the main-RAM overflow
  - detailed monster knowledge remains a future `look`/UX follow-up rather than a `/` responsibility
- Recent resolved items include BUG-1, BUG-LIT, BUG-M1, BUG-X, BUG-RECALL, BUG-EGO-NAME, BUG-DEEP-SPAWN, BUG-XP-PACE, BUG-GEN-CLEAR-C64, BUG-GEN-STALE-TOWN-C64, BUG-GAMEOVER-CLEAR-C64, BUG-DIG-SHIFT-D, BUG-PROMPT-FILTER, BUG-HAGGLE-UI, BUG-HELP-PAGING, `BUG-HELP-ESC-CANCEL-CONTRACT`, BUG-LOOK-HILITE, `BUG-LOOK-TRAP-DOOR`, `BUG-LOOK-WALL-GOLD`, `BUG-C128-LOOK-DOOR-RANGE`, BUG-TITLE-DUALDISK-FRAME, BUG-TOWN-KILL-DRAW, BUG-LOAD-C64, BUG-DESCENT-TOPROW-C64, BUG-INV-STATLINE-C64, `BUG-C128-TOWN-TOPROW-RECUR`, `BUG-TOWN-SIZE-DRIFT`, `BUG-C128-BOOTART-ORDER`, OPT-1, OPT-2, REF-1, `AUDIT-IO-C128`, `REF-INPUT-TABLES`, `REF-C128-TRAMP`, `REF-CONSTS`, the major C128 loader / banking stability repairs, the resident C128 banked combat relocation plus cached `OVL.UI`, 10.4 VDC threat/effect color work, the first `PERF-DG-C128` pass (faster dungeon generation plus visible `GENERATING...` feedback on dungeon transitions), the `dungeon_gen` BFS scratch cleanup, the high-value `TST-5` isolated coverage for disk swap plus renderer decision trees, `FEAT-WIZ`, `FEAT-SEARCH-MODE`, `FEAT-DISK`, and `FEAT-UNIFIED-DISK` / `BUILD-UNIFY`.
- C128 VDC optimization work is paused after the verified left-scroll rollback and subsequent stability regressions; any restart needs a fresh design pass.

## Open Phases / Display Work

| Priority | Item | Difficulty | Benefit | Needed Before C128 -> `main` Merge? | Notes |
|---|---|---|---|---|---|
| Medium | `UI-80` refine the C128 80-column layout to a true Umoria-style left status panel | High | Medium | No | Treat as a refinement of the shipped 80-column baseline, not a contradiction of 10.7 completion. |

## Open Test / Cleanup Work

| Priority | Item | Difficulty | Benefit | Needed Before C128 -> `main` Merge? | Notes |
|---|---|---|---|---|---|
| Medium | `OPT-STATUS-ROW23` split the bottom status row into field-level redraws | Medium | Medium | No | The current status renderer now redraws only dirty rows, but row 23 still clears and repaints `HP`, `MP`, `AC`, `AU`, and hunger/state as a unit. A later optimization pass should keep the forced full-repaint contract for screen/status clears while giving row 23 fixed-width field redraw helpers so single-field changes like mana ticks do not visibly flash the whole bottom row. |
| Low | `OPT-5` further overlays for magic/spells/UI | High | Low | No | Only useful if main-segment pressure returns. |

## Open Features

| Priority | Item | Difficulty | Benefit | Needed Before C128 -> `main` Merge? | Notes |
|---|---|---|---|---|---|
| Medium | `FEAT-BOOT-ART` improve boot presentation beyond the current shipped boot art | High | High | No | C64 now ships the tracked artist PNG through the existing bitmap asset pipeline, while C128 still uses the generated 80-column fallback poster helper. The next art-quality step is C128 source-art parity and any platform-aware touch-up, not more low-level boot plumbing. Optional glint animation remains a later embellishment. |
| Medium | `FEAT-VMS-LOOK-SEMANTICS` move `look` to the VMS-Moria directed ray contract | High | Medium | No | Replace the current drifted `look` behavior with the simpler VMS-style directed ray scan and message flow. Treat this as a redesign, not an incremental bug fix: `look` has already produced repeated regressions in the current port, so the next pass should re-anchor on upstream VMS semantics (directed rays, repeated messages along the ray, no interactive recall handoff) before changing code. |
| Medium | `FEAT-DEPTH` restore original Moria depth semantics (`0-1200` feet in `50`-foot increments) | High | Medium | No | The original games use dungeon depth in feet rather than a hard `0-99` floor abstraction. Rework UI, save/load, recall/wizard depth entry, generation/state contracts, and any tier/deep-spawn assumptions so the port can represent original-style depth values faithfully. |
| Medium | `FEAT-ITEM-STATS` restore upstream-style item stat descriptions and enchant visibility | High | High | No | VMS-Moria `objdes()` and UMoria `itemDescription()` expose per-item magic stats in descriptions, including weapon `(+to_hit,+to_dam)`, armor `[base_ac,+to_ac]`, charges, and relevant `p1`-style bonuses. The Commodore port currently hides all of that and only carries a simplified single-instance bonus field (`inv_p1`), so enchant weapon/armor effects are real but mostly invisible to the player. A proper pass should decide whether to extend the item instance model toward separate `to_hit` / `to_dam` / `to_ac` fields or preserve the simplified model and at least render the stored bonus consistently, then thread that through inventory, equipment, stores, identify/recall text, and any spell/scroll messaging that depends on visible stat changes. |
| Low | `FEAT1` expand mage/priest spells from 16 to 31 each | High | Medium | No | Requires UI pagination and likely extra overlay pressure. |
