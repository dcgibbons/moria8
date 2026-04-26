# Active Task Scratchpad

Active-only backlog. Completed task scratchpad material through 2026-04-26 is archived in `commodore/BUILDPLAN_HISTORY.md`.

## Active Backlog

- [ ] `OPT-C128-BOOTART-PACK`: re-approach C128 boot-art packing only after adding a live/poster-validating smoke or equivalent visual proof.
- [ ] `BUG-C128-INPUT-CONTRACT-REDESIGN`: finish the C128 run/input redesign without widening the C64/C128 decoded command split.
  - [ ] Keep command decoding and modal/prompt input on the existing decoded path.
  - [ ] Add unit and guard coverage proving the run sampler no longer depends on PETSCII and ignores modifier-only rows.
  - [ ] Verify with `make test64` and `make test128-fast-smoke`.
- [ ] `FEAT-NEW-SPELL-HARDENING`: harden newly added spell/prayer paths with representative product-path coverage.
- [ ] `BUG-SHARED-INV-OVERLAY-DIRECT-SELECT`: fix direct selection from inventory overlays when filtered entries are visible-letter mapped.
- [ ] `BUG-TRAP-HP-UNDERFLOW`: reproduce the rockfall-trap HP corruption from the live gameplay path before attempting a product fix.
- [ ] `BUG-IDENTIFY-FILTERED-ITEM-CHOOSER`: triage and fix filtered item chooser behavior for identify flows.
- [ ] `BUG-IDENTIFY-MISSING-CATEGORY-NOUN`: triage and fix missing category noun text in identify flows.
- [ ] `BUG-C128-TITLE-CACHE-1`: cache C128 title art for the whole session so failed title-load returns do not depend on the currently mounted disk.
  - [ ] Route the C128 title loader through the cache owner in runtime-common code without regressing mounted-save-disk load fixes.
  - [ ] Add focused C128 automation for boot to title, mount save disk in drive 8, press `L`, fail load, and return to the full title-art menu.
- [ ] `BUG-C128-TITLE-SCREEN-FLASH`: triage the C128 title screen flash regression.
- [ ] `BUG-C128-TITLE-L-RUNTIME-REENTRY`: triage title `L` runtime re-entry safety.
- [ ] `BUG-C128-TITLE-L-GAMEWRITTEN-SAVE-REPRO`: reproduce the game-written save title-load path.
- [ ] `BUG-C128-DRIVE8-ROUNDTRIP-TEST-TRUST`: harden the drive-8 roundtrip test so it can be trusted as closure evidence.
- [ ] `BUG-C64-LOAD-VALIDATE-ONLY-SETUP`: keep C64 first-time load to validation only; initialization belongs to explicit setup/save paths.
- [ ] `BUG-C64-SINGLE-DRIVE-LOAD-PROMPT`: repair C64 single-drive load prompting.
- [ ] `BUG-C64-SHIFT-S-STACK-JAM`: triage the C64 `Shift+S` stack/JAM path.
- [ ] `FEAT-BOOT-ART` follow-ups:
  - [ ] Phase 4: better final art.
  - [ ] Phase 5: glint animation.
- [ ] C64 rendering backlog:
  - [ ] First descent from town can leave garbage on the top row after level generation.
  - [ ] Re-check whether the old "C64 loading is currently broken outside this feature scope" note is still live or stale.
  - [ ] Add dedicated disk-backed C64 title-load smokes for the real `L` path.
- [ ] `FEAT-VMS-LOOK-SEMANTICS` / `BUG-LOOK-HILITE` follow-up:
  - [ ] Decide whether to keep the compact VMS-style baseline or fund a larger parity push later.
  - [ ] Add C128 unit/smoke coverage for shared `look` changes.
  - [ ] Run full regression gates before human playtesting.
  - [ ] Cover the remaining directed-`look` matrix: directions, invalid input, remembered dark entities, range/cone bounds, off-panel targets, screen-coordinate conversion, highlight/flash restore, traversal order, feature/monster/item descriptions, recall handoff, and C64/C128 regression suites.
- [ ] `BUG-LONG-MESSAGE-TRUNCATION-POLISH`: reserve message-row width for `-more-` only when continuation is pending, so exact-fit messages do not truncate unnecessarily.

## Build Plan Cross-References

- [ ] `UI-80`: refine the C128 80-column layout to a true Umoria-style left status panel.
- [ ] `OPT-STATUS-ROW23`: split bottom status row redraws into field-level helpers.
- [ ] `OPT-5`: consider further magic/spell/UI overlays only if main-segment pressure returns.
- [ ] `FEAT-DEPTH`: restore original Moria depth semantics in feet.
- [ ] `FEAT-ITEM-STATS`: restore upstream-style item stat descriptions and enchant visibility.
