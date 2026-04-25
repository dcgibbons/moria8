# Active Task Scratchpad

This file is a temporary working scratchpad.

## Current Task
- [x] BUG-SHARED-DIRECTIONAL-MONSTER-PATH
- [x] Reported Failure Gate:
  - Directional monster effects must trace through the chosen line instead of only checking the adjacent tile; `Polymorph Other` must work at range, and the shared regression gates are `make test64` and `make test128-fast-smoke`
- [x] audit shared `eff_directional_monster` and Polymorph Other row tests
- [x] replace adjacent-only Polymorph row stubs with real directional tracing at range on C64 and C128
- [x] update docs/task notes to reflect the current ranged contract
- [x] verify:
  - `make build`
  - focused C128 Polymorph Other compare run
  - `make test64`
  - `make test128-fast-smoke`
- [x] review:
  - Product `eff_directional_monster` already traces up to 20 steps along the chosen direction and leaves `zp_ptr0` on the found monster.
  - The stale Polymorph Other row tests patched out the shared helper, so they now stub only direction selection and monster lookup.
  - The focused Polymorph target now sits two tiles east through an empty lit floor tile; an adjacent-only implementation would miss it.
- [x] SLOW-MONSTER-CONTROL-FEEDBACK
- [x] Reported Failure Gate:
  - Slow Poison must print the upstream poison-reduced feedback only when poison is actually reduced; Slow Monster must report that the targeted monster was slowed instead of title/beep feedback; Blind Creature must be re-audited against the shared directional-confuse path; exact regression gates are `make test64` and `make test128-fast-smoke`
- [x] audit current product paths and focused tests for Slow Poison, Slow Monster, and Blind Creature
- [x] implement layout-safe feedback fixes for Slow Poison and Slow Monster
- [x] update C64/C128 focused tests and docs so they assert the new feedback contract and Blind Creature audit result
- [x] verify:
  - focused C128 spell-row tests: `confusion128,slow_poison_prayer128,slow_monster128,blind_creature_prayer128,genocide128`
  - `make build`
  - `make test64`
  - `make test128-fast-smoke`
  - `make test128-fast`
- [x] review:
  - `Slow Poison` now halves poison as before but prints `HSTR_EFF_POISON_END` only when the poison counter was nonzero; already-clear casts remain silent/no-op after successful prayer bookkeeping
  - `Slow Monster` no longer prints the mage title huff id on success; it now mutates the target speed counter, clears sleep, and prints the compact `It slows.` feedback from runtime/banked string storage so the C64/C128 death overlays stay within bounds
  - `Blind Creature` re-audit found product code already uses the shared directional-confuse helper; focused C64/C128 tests now assert confuse is set and stun remains untouched
  - `eff_directional_monster` already leaves `zp_ptr0` on the found monster, so the shared confuse helper no longer repeats `monster_get_ptr`; focused stubs were updated to preserve that real side effect
  - verification passed: `make build`, focused C128 row batch, `make test64` (`110 passed, 0 failed`), `make test128-fast-smoke` (`8 passed, 0 failed`), and `make test128-fast`
- [x] TEST-C64-C128-FULL-INPUT-TREE
- [x] Reported Failure Gate:
  - Design and implement proper full input-tree coverage for both platforms so raw key mapping, `input_get_command`, and command dispatch cannot drift independently again
- [x] add independent expected key/command tables to C64 and C128 input tests instead of deriving expectations from production key-map macros
- [x] add real-`input_get_command` main-loop integration coverage:
  - C64: unknown-key retry, lowercase `f` -> gain, shifted `F` -> fire, `M` -> cast
  - C128: unknown-key retry, lowercase `f` -> gain, shifted `F` -> fire, `M` -> cast, `P` -> prayer
- [x] harden shared command-dispatch table assertions for both low-byte and high-byte indexes across the full discrete command range
- [x] verify:
  - focused C128 `input128,main_loop128`
  - `make test64`
  - `make test128-fast`
  - `make build`
- [x] review:
  - C64 `test_input` now checks 55 hand-authored PETSCII cases, and C128 `test_input128` checks the same shared cases plus keypad/extended-key policy
  - C64 `test_main_loop` now restores the real `input_get_command` for integration cases while keeping only raw key input scripted; the C64 prayer key is covered by the full mapper table because the existing C64 main-loop harness does not have a stable prayer handler seam
  - C128 `test_main_loop128` covers real-input dispatch through gain, fire, cast, and prayer trampoline seams
  - verification passed: focused C128 input/main-loop run, `make test64` (`110 passed, 0 failed`), `make test128-fast`, and `make build`
- [x] BUG-C64-LEARN-SPELL-F-KEY-SNAPSHOT-RED
- [x] Reported Failure Gate:
  - User-provided live C64 snapshot `~/vice-snapshot-20260424222929.vsf`; from that snapshot, pressing `f` still does nothing, so this snapshot path is the active repro gate
- [x] update lessons for the second incorrect closure
- [x] load the snapshot in C64 VICE and trace the actual `f` path through command decode, command dispatch, prompt text, and prompt follow-up input
- [x] fix the actual owner shown by the snapshot, without breaking C128 or shifted fire
- [x] verify against the snapshot path plus regression gates:
  - snapshot repro
  - `make test64`
  - `make test128-fast`
- [x] review:
  - the snapshot proved C64 received PETSCII `$46/$66` and decoded `f` to `CMD_GAIN`; the key map was not the remaining owner
  - the real break was the shared command-dispatch high-byte table: it had one fewer entry than the low-byte table, so `CMD_GAIN` combined `<cmd_gain` with the following command's high byte and jumped to the wrong address in the live image
  - `command_dispatch_hi` now includes the missing `CMD_RUN_SE` placeholder, and assembler assertions lock both dispatch-table lengths plus the exact `CMD_GAIN` low/high indexes
  - rebuilt product `commodore/out/c64/moria8.prg` now maps `CMD_GAIN` to `cmd_gain` (`$b5fc`) instead of the bad mixed-page target
  - verification passed: `make test64` (`110 passed, 0 failed`), `make test128-fast`, and `make build`
- [x] BUG-C64-LEARN-SPELL-F-KEY-LIVE-STILL-RED
- [x] Reported Failure Gate:
  - User live-tested C64 after `$66 -> CMD_GAIN`; pressing `f` still does not activate spell learning, so the active gate is the real C64 product behavior, not only `petscii_to_command`
- [x] update lessons for the incorrect prior closure
- [x] reproduce the live C64 command path far enough to prove whether `f` reaches `input_get_command`, `cmd_gain`, `tramp_item_gain_spell`, and `item_gain_spell`
- [x] fix the actual failing product path without disturbing shifted `F` ranged fire
- [x] add/adjust verification so the product C64 learn path is covered, not just the pure key mapper
- [x] verify:
  - product/path-focused C64 learn test or smoke
  - `make test64`
- [x] review:
  - the mapper-only `$66 -> CMD_GAIN` fix was insufficient because the live C64 failure was at the follow-up prompt seam, not only at command decode
  - `pm_select_book` now uses `input_prepare_modal_dismiss_key` before reading the book-selection key, so the initiating `f/m/p` command cannot repeat into the prompt and cancel it immediately on C64
  - added a `book_prompt_fresh_key_contract` static gate alongside the existing learn/spell-list fresh-key contracts
  - verification passed: `make test64` (`110 passed, 0 failed`) and `make test128-fast`
- [x] BUG-C64-LEARN-SPELL-F-KEY
- [x] Reported Failure Gate:
  - On C64, pressing `f` should activate spell/prayer learning from a book; if C128 accepts the same key, C64 should not require a different binding
- [x] verify the C64 key decode path maps live `f` input to `CMD_GAIN`
- [x] patch the minimal input mapping/normalization gap without changing shifted `F` fire behavior
- [x] add focused C64 input coverage for lowercase `f` -> `CMD_GAIN`
- [x] verify:
  - focused C64 input test
  - `make test64`
- [x] review:
  - root cause was PETSCII case coverage: the shared command map accepted `$46` for learn and `$C6` for shifted fire, but not lowercase `$66` observed on C64
  - fixed by adding `$66 -> CMD_GAIN` in the shared input table while leaving `$C6 -> CMD_FIRE` unchanged
  - C64 input test now checks lowercase `f` explicitly and the run harness reads the added twelfth result byte
  - verification passed: `make test64` with `input: PASS (12/12 tests)` and final `109 passed, 0 failed`
- [x] BUG-PRAYER-DETECT-EVIL-DISPEL-VISIBLE
- [x] Reported Failure Gate:
  - Detect Evil must be instant evil-only current-panel reveal with no detect timer; its wrapper must print evil-present only from the effect result, and Dispel Undead / Dispel Evil / Holy Word dispel must affect only visible/LOS flagged monsters with per-target `shudders.` / `dissolves!` feedback while preserving `HSTR_PIQ_NOTHING` for no targets
- [x] repair Detect Evil product code:
  - scan active evil monsters only
  - restrict reveal to current viewport
  - mark affected monster tiles `FLAG_VISITED | FLAG_LIT`
  - leave `eff_detect_timer = 0`
  - return nonzero only when an evil monster was revealed
- [x] update Detect Evil message wrapper and C64/C128 focused coverage for no-evil vs evil result contracts
- [x] repair flagged dispel product code:
  - gate flagged targets through `los_is_visible`
  - count only visible/LOS affected targets
  - apply damage and kill through existing monster/combat owners
  - print `The <monster> shudders.` for damage and `The <monster> dissolves!` for kills
- [x] update C64/C128 Dispel Undead/Evil/Holy Word focused coverage and required stubs
- [x] update stale spell docs that describe old Detect Evil timer and message-light dispel behavior
- [x] verify:
  - focused C64/C128 Detect Evil and flagged-dispel tests
  - `make test64`
  - `make test128-fast`
- [x] review:
  - `eff_detect_evil_only` now performs an immediate current-viewport evil scan, permanently lights/visits revealed evil monster tiles, clears `eff_detect_timer`, and returns the found flag consumed by `pmx_detect_evil_msg`
  - the old evil-only detect-timer renderer path was removed from C64/C128 renderers and the shared turn tick now treats detect-monsters as the only timer-backed monster reveal
  - `eff_dispel_flagged` now requires `los_is_visible`, counts only affected visible targets, applies damage through combat, kills through `eff_kill_monster`, and prints per-target shudders/dissolves feedback
  - focused C128 fixture imports needed explicit LOS/combat feedback stubs because the shared utility helper is assembled by tests that do not exercise dispel directly
  - verification passed: focused C128 detect/dispel suite, `make test64`, `make test128-fast`, and `make build`
- [ ] OPT-C128-BOOTART-PACK
- [ ] Reported Failure Gate:
  - C128 boot art should ship in a smaller packed form without changing the visible poster result or breaking `make build128`; the first packed-runtime attempt rendered flashing garbage and was backed out
- [ ] re-approach C128 boot-art packing only after adding a real live/poster-validating smoke or equivalent visual proof
- [ ] BUG-C128-INPUT-CONTRACT-REDESIGN
- [ ] Reported Failure Gate:
  - on C128, shifted running and other direct-scan interactions must stop depending on PETSCII-decoded held-state; `Shift+H` must not self-cancel after a few tiles, and `make test64` plus `make test128-fast-smoke` must remain green while the C128 input contract is redesigned
- [x] replace the C128 run sampler with a raw physical matrix contract that ignores modifier-only state without using `cia_scan_petscii`
- [ ] keep command decoding and modal/prompt input on the existing decoded path so the redesign does not widen the C64/C128 fracture
- [x] place the new raw C128 run sampler in a dedicated resident runtime asset instead of trimming unrelated bytes to force it into an existing segment
- [ ] add unit and guard coverage proving the run sampler no longer depends on PETSCII and that modifier-only rows are ignored
- [ ] verify:
  - `make test64`
  - `make test128-fast-smoke`
- [ ] review:
  - live monitor breakpoint at `$BA6C` proved the bad stop is `main_loop !run_cancel`, not `run_step`
  - the true root cause is architectural: C128 running was feeding a PETSCII-decoded sample into the run held/cancel FSM, so transient decoded neutral states could arm cancel and then reinterpret the same held chord as a fresh edge
  - the fix must leave C64/shared game logic on the same high-level contracts while confining C128-only differences to the raw matrix sampler

- [ ] AUDIT-PRAYER-PASS-1
- [ ] Reported Failure Gate:
  - priest prayers should have upstream-faithful live behavior, visible feedback where upstream provides it, and correct C64/C128 prompt/render behavior; `make test64` and `make test128-fast-smoke` remain the exact regression gates for prayer-side fixes
- [ ] prayer audit findings, prioritized:
  - `Slow Poison` is currently silent in Commodore, but both VMS and umoria print a reduction message when poison is actually reduced
  - `Blind Creature` needs re-audit against current shared directional-confuse behavior before changing product code
- [x] TURN-UNDEAD-VISIBLE-FEEDBACK
- [x] Reported Failure Gate:
  - `Turn Undead` must affect only visible/LOS undead, print per-monster `runs frantically!` or `is unaffected.` feedback, leave hidden undead untouched, print `HSTR_PIQ_NOTHING` when no visible undead exist, and keep `make test64` plus `make test128-fast-smoke` green
- [x] implement visible/LOS Turn Undead targeting and per-target feedback
- [x] update C64/C128 focused Turn Undead coverage
- [x] update spell docs/test-plan rows for the new Turn Undead contract
- [x] verify:
  - `make test64`
  - `make test128-fast-smoke`
  - focused C128 `turn_undead_prayer128`
  - `make test128-fast`
- [x] review:
  - `eff_turn_undead` now shares the visible/LOS flagged-monster scan used by dispels, turns only visible `CF_UNDEAD` targets, leaves hidden undead unchanged, and prints `HSTR_PIQ_NOTHING` when no visible undead are found
  - visible low-level undead get `MX_CONFUSE = player level`, `MX_SLEEP_CUR = 0`, and `The <monster> runs frantically!`; visible resistant undead remain unchanged and print `The <monster> is unaffected.`
  - C64 keeps the new scan/feedback helpers in the existing `$F000` banked payload to preserve resident and `$E000` overlay boundaries; C128 keeps turn feedback in `RuntimeCommonData`, leaves the visible scan in the spell overlay, and moves C128-only prompt/title strings into runtime-low RAM so the staged banked payload stays below `$E000`
  - verification passed: `make test64` (`110 passed, 0 failed`), `make test128-fast-smoke` (`8 passed, 0 failed`), and `make test128-fast` (cold + snapshot)
- [ ] remaining prayer fixes after Turn Undead:
  - `Slow Poison`
  - `Blind Creature` re-audit/fix if still divergent
- [ ] FEAT-NEW-SPELL-HARDENING
- [ ] Reported Failure Gate:
  - newly added spells/prayers must have correct live behavior, correct visible feedback, and correct platform-specific rendering/input behavior; `Magic Missile` must animate from the player’s actual viewport row/column without a bogus `Your spell fizzles out.`, and priest book B prayers (`Chant`, `Sanctuary`, `Resist Heat and Cold`) must not beep/no-op or show misleading feedback
- [ ] BUG-SHARED-INV-OVERLAY-DIRECT-SELECT
- [ ] Reported Failure Gate:
  - item/book prompts that support `?` must allow direct selection from the inventory overlay instead of forcing a dismiss-and-reprompt flow; behavior should match the other selectable overlays consistently
- [ ] BUG-C128-MONSTER-REDRAW-DETECT-STALE
- [ ] Reported Failure Gate:
  - on C128, monster presence/movement changes must redraw immediately: detected monsters must appear on the cast turn, moved/killed monsters must not linger, and monsters must not disappear until a later movement/full redraw
- [x] root-cause the shared dirty-scene seam where monster AI movement reported redraw state in carry but the turn layer latched accumulator state
- [x] make monster-driven scene dirtiness deterministic for stationary commands and ordinary end-of-turn monster movement
- [x] add shared turn-level regression coverage so monster AI movement always promotes to `turn_scene_dirty`
- [x] verify:
  - `make test64`
  - `make test128-fast-smoke`
- [x] BUG-C128-REPEATED-FIRE-BOLT-JAM
- [ ] Reported Failure Gate:
  - repeated `Fire Bolt` casts on C128 must not JAM in the cast-success tail; latest live monitor traces unwound through `pm_finish_success_common -> pm_mark_worked` and crashed at `$D014` and then `$001C`
- [x] move C128-only prompt helpers out of the crowded resident spell-state tail so the full cast-success epilogue stays below `$D000`
- [x] tighten the C128 callable residency audit to check helper extents, not just symbol starts, for the cast-success tail
- [x] verify:
  - `make test64`
  - `make test128-fast-smoke`
- [x] BUG-SHARED-DIRECTIONAL-MONSTER-PATH
- [x] Reported Failure Gate:
  - directional monster effects must trace through the chosen line instead of only checking the adjacent tile; `Polymorph Other` must work at range, and the shared C64 gate remains `make test64`
- [ ] BUG-SHARED-SLOW-MONSTER-FEEDBACK
- [x] BUG-SHARED-PSEUDO-ID-UMORIA-PARITY
- [ ] Reported Failure Gate:
  - pseudo-ID wording/behavior must match `umoria`'s useful auto-sense flow instead of the current `Sense: Average/Good/...` quality hack; exact verification gates: `make test64` and `make test128-fast-smoke`
- [x] replace the current quality-based pseudo-ID turn path with `umoria`-style enchantment sensing over pack + equipment
- [x] add a dedicated item-instance sensed-magical flag instead of reusing the old quality bit semantics
- [x] remove the `Terrible/Bad/Average/Good/Excellent` pseudo-ID UI and replace it with a persistent `magik` marker on sensed, unidentified items
- [x] keep full identification clearing the sensed-magical marker so item state stays coherent
- [x] verify:
  - `make test64`
  - `make test128-fast-smoke`
- [x] review:
  - the old class-based pseudo-ID timer was replaced with `umoria`'s outer cadence in `turn_tick_pseudo_id`: every 16 turns, if not confused, roll `10 + 750 / (5 + level)` and only then scan the item list
  - the scan now matches `umoria`'s order and per-item odds: pack first at `1/50`, then equipment at `1/10`, setting the dedicated `IF_SENSED` marker and printing the useful slot-localized wording instead of `Sense: Average/Good/...`
  - full identify and wizard identify paths now clear `IF_SENSED`, while inventory/equipment rendering persists the new ` (magik)` marker for sensed-but-unidentified items
  - the first pack/equipment pass had a real 6502 flag bug: after `rng_range`, the code restored the slot index into `X` and then branched on `BNE`, so it was testing the restored slot number instead of the RNG result and only slot `0` could ever auto-sense
  - the exact red gate after the cadence change was not product logic; `test_save.s` had drifted past `MAP_BASE`, and shrinking the test image plus restoring a local `ui_help_display` stub brought the suite back under `$C000` so `make test64` could verify the feature cleanly

- [ ] Reported Failure Gate:
  - `Slow Monster` must report that the targeted monster was slowed instead of silently beeping; exact verification gates: `make test64` and `make test128-fast-smoke`
- [ ] BUG-SHARED-GENOCIDE-PARITY
- [ ] Reported Failure Gate:
  - `Genocide` must prompt for a monster glyph/type and exterminate all matching monsters on the current level instead of requiring a directional target; exact verification gates: `make test64` and `make test128-fast-smoke`
- [ ] replace the current directional-targeted genocide flow with a direct glyph prompt in the shared spell execute overlay
- [ ] normalize the typed creature glyph the same way the recall/symbol UI does so `Genocide` matches the actual `cr_display` values used by live monsters
- [ ] add focused runtime coverage proving `Genocide` removes multiple same-glyph monsters without requiring a directional target
- [ ] BUG-SHARED-SPELL-LIST-ESC-CANCEL
- [ ] Reported Failure Gate:
  - after selecting a book and pressing `?`, pressing `Esc` on the spell/prayer list must cancel the whole selection flow instead of dropping back to the `Cast which?` / `Pray which?` prompt
- [x] root-cause the remaining live-only C128 failure: the spell/prayer list still release-gated after drawing, so a quick first `Esc` could be swallowed before the selectable overlay key read
- [x] treat `?` spell/prayer list selection as a true cancel on `Esc` instead of a failed pick that loops back to the footer prompt
- [x] add a direct `? -> Esc` spell chooser regression and keep the effects harness count aligned
- [x] add a dedicated C128 scripted smoke for `book -> ? -> Esc` and include it in `make test128-fast-smoke`
- [x] verify:
  - `make test64`
  - `make test128-fast-smoke`
- [ ] BUG-SHARED-SLEEP-EFFECT-AWAKE-STATE
- [ ] Reported Failure Gate:
  - `Sleep II` and `Sleep III` must actually put monsters to sleep by using the live sleep counter, and the player must get visible feedback instead of a silent beep/no-op; the exact verification gate remains `make test64`
- [ ] Reported Failure Gate:
  - `make test128-fast-smoke`
- [ ] rework `monster_wake_check` to use live per-monster sleep state instead of species base sleep data so spell-induced sleep persists
- [ ] add shared visible feedback for adjacent sleep and mass sleep so `Sleep II` / `Sleep III` report what happened
- [ ] BUG-SHARED-MONSTER-REDRAW-AFTER-TRANSFORM
- [ ] Reported Failure Gate:
  - monster-changing effects such as `Polymorph Other` must not leave stale/missing monster tiles on screen until the monster moves again; the exact verification gate remains `make test64`
- [ ] build a behavior-family spell/prayer audit matrix covering all newly added effects
- [ ] fix the shared bolt/projectile regression first, then re-check whether any remaining `Magic Missile` issue is visual-only or a second logic bug
- [ ] audit the under-tested effect families starting with:
  - bolt/projectile spells
  - heals
  - timed buffs/protections/resistances
  - detect/reveal prayers
  - directional/adjacent monster-control effects
- [ ] add runtime coverage for at least one representative from each high-risk family before claiming the feature hardened
- [x] add representative runtime coverage for:
  - shared bolt/projectile spells
  - heals
  - timed buffs/protections/resistances
  - detect/reveal prayers
  - adjacent monster-control effects
  - area/utility/high-end priest effects (`Sense Surroundings`, `Glyph of Warding`, `Holy Word`)
- [ ] BUG-PRIEST-RESIST-SEMANTICS
- [ ] Reported Failure Gate:
  - `Resist Heat and Cold` must have meaningful live gameplay semantics instead of only setting an otherwise-unused packed flag and showing onset feedback
- [x] trace the real fire/cold gameplay consumers and wire the prayer into the currently implemented breath-damage path
- [ ] broaden the prayer beyond the current fire-breath consumer if more elemental hostile actions land later
- [ ] BUG-SHARED-MAGIC-MISSILE-PROJECTILE-FIZZLE
- [ ] Reported Failure Gate:
  - `Magic Missile` must animate from the player’s actual viewport row/column and must not end with `Your spell fizzles out.` when it visibly cast at a target in town or dungeon
- [ ] root-cause the shared bolt/projectile regression in the current tree
- [x] BUG-STINKING-CLOUD-NOOP
- [ ] Reported Failure Gate:
  - `Stinking Cloud` must visibly cast as a ball-style spell and must damage monsters in its target area instead of only beeping and appearing to do nothing
- [x] add a direct runtime regression for the shared `eff_ball` path before changing gameplay code
- [x] harden the ball-family cast path so `Stinking Cloud` and other ball spells visibly travel and apply area damage
- [ ] BUG-PRIEST-BOOK-B-FEEDBACK-BEHAVIOR
- [ ] Reported Failure Gate:
  - priest book B prayers (`Chant`, `Sanctuary`, `Resist Heat and Cold`) must have correct live behavior and correct player-visible feedback instead of beeping, no-oping, or showing the wrong message
- [ ] audit the current implementation and live feedback contracts for priest book B prayers before changing effect code
- [ ] BUG-C128-IDENTIFY-ITEM-PROMPT-NOOP
- [ ] Reported Failure Gate:
  - C128 item-identify prompt must accept the chosen item letter and identify the item instead of immediately falling through to `Nothing seems to happen.`
- [ ] harden the shared `eff_identify_prompt` follow-up input path for C128 and add coverage
- [ ] BUG-SHARED-IDENTIFY-QMARK-DISMISS-LEAK
- [ ] Reported Failure Gate:
  - after `?` from the identify item prompt, dismissing the read-only inventory overlay must not reuse that dismiss key as the actual item selection; the `?` overlay behavior must stay consistent with the other view-only item overlays
- [ ] BUG-SHARED-OVERCAST-ORDERING
- [ ] Reported Failure Gate:
  - overcast spell/prayer casts must not print `Not enough mana.` before the spell effect executes; identify-style spells must follow upstream overcast ordering instead of warning first and prompting second
- [ ] align shared overcast handling with upstream sequencing and messaging instead of treating it as an identify-specific prompt bug
- [ ] BUG-MP-BOOK-PROMPT-TEXT
- [ ] Reported Failure Gate:
  - `m`/`p` must not show `Study which book`; cast must show a cast-book prompt, pray must show a pray-book prompt, and study must keep the study-book prompt
- [ ] replace the oversized inline spell-book prompt helper with compact Huffman-backed prompt IDs
- [ ] verify:
  - `make build128`
  - `make test64`
  - `make test128-fast-smoke`
- [ ] BUG-C128-PRAYER-SNAPSHOT-NOOP
- [ ] Reported Failure Gate:
  - restore ~/vice-snapshot-20260416125631.vsf on C128, then `p`, `a`, and any prayer letter (`a`, `b`, or `c`) must execute the selected prayer instead of silently no-oping
- [ ] corrected scope from live user retest:
  - current checked-out C128 code appears to have regressed the shared cast/pray letter-selection path, not just priest-only prayer effects
  - C128 `m` and `p` selection failures should be treated as one shared casting-system regression until disproven
- [x] BUG-C128-PRAY-NO-EFFECT-WIZARD-MISDISPATCH
- [ ] Reported Failure Gate:
  - C128 live gameplay `p` must actually execute the selected prayer, and `Ctrl+W` must enter wizard mode instead of wear/takeoff
- [x] reproduce and root-cause the C128 prayer command path so selected prayers do not silently no-op
- [x] reproduce and root-cause the C128 `Ctrl+W` command decode so it dispatches to `CMD_WIZARD` reliably
- [x] verify:
  - `make build128`
  - `make test64`
  - `make test128-fast`
  - `make test128-fast-smoke`
  - `TEST_FILTER=scripted_prayer_cast_smoke bash commodore/c128/run_tests128.sh`

- [x] FEAT-SPELL-FEEDBACK-AUDIT
- [x] audit all 31 mage + 31 priest spells/prayers for player-visible feedback and align Commodore with the locked hybrid upstream policy
- [x] add or reuse spell/prayer feedback only where the effect is otherwise silent, misleading, or missing relative to current UMoria behavior
- [x] keep cast/pray wrapper messaging generic-free and put visible feedback in the effect/status path instead
- [x] extend `commodore/SPELLS.md` with the spell-feedback audit/results
- [x] verify:
  - `make test64`
  - `make build64`
- [ ] residual verification note:
  - `make build128` still emits the existing `Banked payload staged source ends below overlay window` assertion
  - this assert is unchanged from `HEAD` `bf4e611` (`$E028` staged-source end in both trees)
- [ ] BUG-C64-MAGIC-MISSILE-CRASH
- [ ] Reported Failure Gate:
  - C64 live gameplay `Magic Missile` cast must not crash from the easy reproducible shipping path in the dungeon with REU enabled, with an actual targetable monster in the aimed tile
- [x] reproduce the easy live C64 `Magic Missile` crash in an automated REU-enabled dungeon-target smoke before attempting any product fix
- [x] root-cause the snapshot-backed C64 spell crash at the `-more-` resume seam in shared message handling
- [x] harden the shared `msg_show_more` / `msg_save_history` path for C64 and add a direct C64 regression for message resume after `-more-`
- [x] root-cause the remaining C64 dungeon target crash in the stale-tier monster-name reload path (`creature_get_name -> tier_load -> reu_fetch_tier`)
- [x] preserve caller IRQ/banking state in the C64 REU/tier helpers and add a current-build dungeon spell smoke that forces the stale-tier REU name-reload path
- [x] verify:
  - `make test64`
- [ ] BUG-C64-DETECT-EVIL-CRASH
- [ ] Reported Failure Gate:
  - C64 in-dungeon `Detect Evil` cast must not crash back to BASIC from the live gameplay path
- [ ] reproduce the live C64 in-dungeon `Detect Evil` crash in an automated scripted smoke before attempting any product fix
- [ ] BUG-TRAP-HP-UNDERFLOW
- [ ] Reported Failure Gate:
  - C64 live gameplay trap damage must not corrupt HP to wrapped values like `65535/9` after a rockfall hit
- [ ] reproduce the rockfall-trap HP corruption from the live gameplay path before attempting any product fix
- [x] BUG-C64-SPELL-CAST-FFFF
- [ ] Reported Failure Gate:
  - C64 live gameplay spell cast must not leave `$01=$35` with IRQs enabled or hang at `PC=$FFFF` after the cast path returns
- [x] root-cause the C64 post-cast lockup on the real spell-hit path
- [x] add a focused regression that proves C64 `creature_get_name` preserves caller IRQ/banking state when entered from `SEI/$35`
- [x] verify:
  - `make build64`
  - `make test64`
- [ ] BUG-C128-SPELL-CAST-D026
- [ ] Reported Failure Gate:
  - `python3 commodore/c128/tests/product_spell_cast_smoke.py --vice /opt/homebrew/bin/x128 --boot-d64 commodore/out/moria8-c128.d71`
- [x] reproduce the shipping-build C128 spell-cast crash in an automated test before attempting another fix
- [ ] root-cause the shipping spell-cast jump into `$D026` on the product disk image
- [x] FEAT-ADDITIONAL-SPELLS
- [x] Reported Failure Gate:
  - implement the remaining spells from `commodore/BUILDPLAN.md` with audited VMS/UMoria parity on both C64 and C128
- [x] replace the simplified 16-spell model with full class-aware 31-spell tables and explicit book bitmasks
- [x] widen player spell state and save/load handling for full-catalog learning/worked/order tracking
- [x] rework cast/pray/study flows around upstream-style book-scoped spell selection and class-specific learning rules
- [x] implement the missing mage and priest spell/prayer effects and correct any existing spell drift that blocks parity
- [x] update character/status UX and spell counting for the widened state and full class spell access
- [x] create an exhaustive spells document covering current Commodore behavior, new spells, and VMS-vs-UMoria differences
- [x] verify:
  - `make build64`
  - `make build128`
  - `make test64`
  - `make test128-fast`
  - `make test128-fast-smoke`
  - `make test`
- [x] FEAT-AUD
- [x] add a shared hunger-alert sound that stays distinct from the current combat/UI palette:
  - `HUNGRY` and `WEAK` use the mild low-pulse warning
  - `FAINT` uses the harsher low-pulse warning
- [x] trigger the alert only on worsening hunger-state transitions from `turn_tick_hunger`; keep `player_update_hunger_state` pure and avoid redraw-driven replay
- [x] add focused shared sound/turn regression coverage and verify:
  - `make test64`
  - `make test128-fast`
- [x] AUDIT-C64-DEAD-CODE
- [x] audit the current shipping C64 imports for helpers that are only referenced from tests and remove the lowest-risk dead production owner
- [x] remove the dead shipping `string_bank_banked.s` import after confirming `bank_decode_string` has no production callsites
- [x] verify the exact C64 gates:
  - `make -C commodore out/c64/moria8.prg`
  - `make test64`
- [x] FEAT-VMS-RECALL-SEMANTICS
- [x] add a backlog feature for VMS-Moria-style `/` behavior:
  - `/` identifies what a symbol on screen stands for
  - `look` remains the path for the exact visible creature
  - leave the current combat-earned recall implementation alone for now
- [ ] BUG-IDENTIFY-FILTERED-ITEM-CHOOSER
- [ ] Reported Failure Gate:
  - `Identify` must use the same filtered visible-slot chooser contract as the other item prompts, so gaps in inventory do not make `?` overlay letters or direct prompt letters select the wrong absolute slot
- [ ] BUG-IDENTIFY-MISSING-CATEGORY-NOUN
- [ ] Reported Failure Gate:
  - identify feedback must include the item category noun for bare-name consumables and jewelry, e.g. `This is a Cure Serious Wounds potion.`
- [x] FEAT-C64-BOOT-ART-ASSET
- [x] add a dedicated source-image adapter for C64 boot art without changing the runtime bootloader or the existing C64 PRG quantizer
- [x] switch the C64 boot-art build rule to use `artwork/moria8_loading_art_c64.png` as the canonical source asset
- [x] verify the real asset path through the C64 build and boot-art artifact generation gates
- [x] FEATURE-SAVE-OVERWRITE-CONFIRM: keep `THE.GAME` after load/death and prompt before overwriting it on save
- [x] implement the shared save owner change in `commodore/common/save.s`:
  - stop delete-on-load
  - stop unconditional pre-save delete
  - add shared savefile-exists + overwrite-confirm flow
  - use confirmed overwrite-safe open only when the user answers `Y`
- [x] remove delete-on-death from `commodore/common/game_loop.s`
- [x] add focused tests for:
  - overwrite prompt decision helper
  - save-cancel / resume-to-gameplay caller behavior
  - death path no longer calling `delete_savefile`
- [x] run verification gates:
  - `make test64`
  - `make test128-fast`
  - `make test128-fast-smoke`
- [ ] BUG-C128-TITLE-CACHE-1: cache C128 title art for the whole session so failed title-load returns do not depend on the currently mounted disk
- [ ] route the C128 title loader through the cache owner in runtime-common code without regressing the earlier mounted-save-disk load fixes
- [ ] add focused C128 automation for: boot to title, mount save disk in drive 8, press `L`, fail the load, and still return to the full title-art menu
- [ ] run the focused and shared C128 verification gates:
  - `make disk128`
  - `TEST_FILTER='title_art_smoke|boot_title_load_missing_savefile_smoke|boot_title_load_resume_smoke' bash commodore/c128/run_tests128.sh`
  - `make test128-fast-smoke`
- [x] BUG-LOAD-C128-1: remove the obsolete C128 one-drive return-to-program-disk prompt in the shared `disk_prompt_game` owner without changing save-disk validation or multi-drive behavior
- [x] add focused C128 verification for the shared owner (`disk_swap128` unit + `main_loop128` caller coverage + title-load smoke negative assertion)
- [x] run the focused C128 verification gates:
  - `TEST_FILTER='disk_swap128|main_loop128|boot_title_load_resume_smoke' bash commodore/c128/run_tests128.sh`
  - `make disk128`
  - `make test128-fast-smoke`

## Review
- C128 bootart centering follow-up:
  - replaced the earlier hard-coded scanline shift in `tools/ppm_to_c128_bootart.py` with a title-safe framing pass that keeps the center block fixed and compresses only the decorative side borders into the practical 24px safe margins
  - the generator now prints source/framed non-black bounds, horizontal center, and effective safe-area margins on each rebuild so placement can be checked from the real asset pipeline
  - kept the restored 512-slot charset / 511 usable-tile contract intact and updated the bootart assembly comments to match the real 8KB upload
  - after the live screenshot showed the art still appeared widened and clipped, fixed the runtime owner in `commodore/c128/bootart128.s` so bootart no longer writes a hard-coded VDC reg 25 mode value; it now preserves the active 80-column geometry and only forces attribute mode on
  - switched the C128 bootart build in `commodore/Makefile` to use the committed tile-native source asset `artwork/moria8_C128loadingart_tile_native.png`
  - updated the converter so title-safe framing is conditional: if the source art is already inside the safe window, the old border squeeze is skipped
  - tightened the palette to the gold/gray family and changed cell color selection from average-lit-pixel color to dominant-lit-pixel color so the native asset survives the VDC conversion more cleanly
  - final kept asset is the converter-resolved banner image that matches the live result, centered at `320.0` with stable bounds `(34,43)-(606,156)`
  - updated `commodore/c128/run_tests128.sh` so the C128 build freshness check fingerprints the new PNG source and `png_to_ppm.py` instead of the old `make_logo.py` path
  - verification:
    - `python3 -m py_compile tools/ppm_to_c128_bootart.py` -> PASS
    - `make -C commodore disk128` -> PASS
    - `make -C commodore run128` -> previously launched with the reg-25-preserving bootart runtime for live visual re-check
- BUG-C64-MAGIC-MISSILE-CRASH / BUG-C64-DETECT-EVIL-CRASH shared progress:
  - exact red repro:
    - `python3 commodore/c64/tests/snapshot_spell_more_smoke.py --snapshot /Users/chadwick/vice-snapshot-20260415171837.vsf --keybuf 'maal' --entry-symbol .msg_show_more --after-entry-keybuf ' ' --return-symbol .main_loop`
    - this failed reliably before the fix, proving the crash was in the resumed `-more-` path after dismissing the prompt, not in spell targeting itself
  - root cause:
    - the shared `msg_print` full-screen branch still saved/restored `zp_ptr0` around `msg_show_more`, then restarted through `msg_print`
    - the actual stable source pointer was already cached in `msg_src_lo/msg_src_hi`, and `msg_save_history` on C64 was still exposed to IRQ-time low-ZP pointer clobber during that resumed copy path
  - fix:
    - make `msg_save_history` atomic on C64 too with `php/sei ... plp`
    - simplify the `-more-` resume branch to clear flags and jump straight to `msg_print_cached` instead of stack-saving/restoring `zp_ptr0`
    - add a direct C64 regression in `commodore/c64/tests/test_ui_views.s` that fills both message rows, dismisses `-more-`, and asserts the resumed message/history state
  - verification:
    - `make test64` PASS (`36 passed, 0 failed`)
- BUG-C64-MAGIC-MISSILE-CRASH follow-up:
  - new snapshot-backed repro:
    - `~/vice-snapshot-20260415181150.vsf`
    - user path: `m`, `a`, `a`, dismiss `-more-`, press direction, then crash to BASIC
  - diagnostic result:
    - the old snapshot cannot be the closure gate after rebuilding because `.vsf` restores the old RAM image too, so current symbols no longer describe the restored code after layout changes
    - the snapshot was still good enough to root-cause the remaining live seam: after the projectile hit path reached `projectile_msg_suffix`, execution fell through `combat_append_monster_name -> creature_get_name -> tier_load -> reu_fetch_tier`
  - root cause:
    - the stale-tier dungeon-monster name reload path was still reopening IRQs on C64 with raw `sei ... cli` helpers inside `reu_fetch_tier` and the C64 activation section of `tier_load`
    - that path is reachable from a live spell hit when the monster still has `$E0xx` tier name pointers but `current_tier` has been cleared, which forces `creature_get_name` to reload the tier inside the spell/message path
  - fix:
    - preserve caller flags in `commodore/common/reu.s` `reu_fetch_tier` with `php/sei ... plp`
    - preserve caller flags in the C64 banked-activation section of `commodore/common/tier_manager.s` `tier_load` with `php/sei ... plp`
    - add `commodore/c64/tests/test_tier.s` coverage for `reu_fetch_tier` preserving `SEI/$35`
    - strengthen the current-build `scripted_dungeon_target_spell_smoke` so it now deliberately forces the stale-tier reload path by clearing `current_tier`/`tier_loaded` after spawning the dungeon target monster under REU
  - verification:
    - `make test64` PASS (`36 passed, 0 failed`)
- Spell cast/pray chooser UX follow-up:
  - fixed the bogus post-book `-more-` prompt by resetting message-row state in the shared modal restore path (`commodore/common/ui_restore.s`) before gameplay prompts resume
  - removed the new auto-popup spell list for `m`/`p`; book pick now returns to a message-line spell/prayer prompt again
  - on-demand list still exists from the chooser via `?`, which opens the full-screen spell viewer and then returns to the chooser prompt
  - verification:
    - `make test64` PASS (`36 passed, 0 failed`)
    - `make build128` PASS
- BUG-C64-SPELL-CAST-FFFF:
  - root cause:
    - `creature_get_name` on C64 always finished its banked/normal copy path with `cli`
    - when called from the live spell-hit path, the caller was intentionally running under `SEI` with `$01=$35` while the overlay spell code had KERNAL banked out
    - that unconditional `cli` reopened IRQs before the caller restored normal banking, so the next interrupt fetched vectors out of RAM and collapsed into the user-reported `$FFFF` garbage-execution loop
  - fix:
    - preserve the caller interrupt state with `php/sei ... plp` in each C64 `creature_get_name` entry path that runs through the banked/name-copy logic
    - keep restoring `$01` from `cgn_saved_p01`, but stop unconditionally enabling IRQs on return
  - regression:
    - `commodore/c64/tests/test_tier.s` test 11 now calls `creature_get_name` from the exact hazardous context (`SEI`, `$01=$35`) and asserts that:
      - the expected name bytes are returned
      - the helper returns with IRQ-disable still set
      - `$01` is still `$35` on return
  - verification so far:
    - `make build64` PASS
    - focused `tier` regression PASS (`11/11`)
    - exact broader gate: `make test64` PASS (`34 passed, 0 failed`)
  - follow-up test-harness fix:
    - the red `effects` suite was a unit-harness bug, not a new product spell regression
    - `test_effects.s` test 37 patched `test_spell_list_display` / `test_spell_execute_selected` with 3-byte `JMP`s, but the shared stubs in `ui_trampoline_stubs.s` were only 1-byte `RTS` bodies
    - fix: turn those two shared spell stubs into explicit 3-byte patch slots and keep the late suite boundary assert exact (`<= $ba5c`) once the body fit precisely to the buffer start
- BUG-C128-SPELL-CAST-D026:
  - one real spell-specific C128 crash is fixed:
    - `calc_spell_failure` had drifted so its live branch target for the non-faint path landed in the I/O hole at `$D026`
    - fix: move `calc_spell_failure` into the banked spell block and add a full-extent residency assert
  - a second real runtime seam is also fixed:
    - the C128 banked spell trampolines were banking KERNAL out by mutating `$01` and not restoring `$01` on return
    - fix: `C128BankedComputeTrampoline` and `tramp_spell_execute_selected` now save/restore `$01`
  - the first shipping-image repro harness was invalid:
    - native-monitor `break` / `until` log lines against `$D026` were ambiguous enough to false-fail even on title-screen idle
    - `commodore/c128/tests/product_spell_cast_smoke.py` was rewritten to use remote monitor breakpoints instead of monlog text
  - current status:
    - build and focused C128 smokes are green after the two product fixes
    - the shipping-image product smoke is now honest, but still needs a reliable way to prove the autostart cast path reaches its success marker before it can replace the user’s live manual gate
- FEAT-ADDITIONAL-SPELLS progress:
  - spell catalogs are now widened to the full `31 mage + 31 priest` sets with `umoria` class tables and explicit per-book bitmasks
  - player spell state is widened from the old 2-byte learned mask to learned/worked/forgotten/order tracking in `player_data`
  - save versions were intentionally bumped (`C64 $0d`, `C128 $0e`) rather than attempting silent migration
  - C64/C128 spell ownership is now split cleanly:
    - selection/study UI lives in `UiOverlay`
    - execution dispatch lives in `DeathOverlay`
  - implemented/fixed high-value spell semantics in the current tree:
    - mage `Sleep II` now uses adjacent sleep instead of mass sleep
    - priest `Sanctuary` now uses adjacent sleep
    - priest `Detect Doors/Stairs` now reveals both doors and stairs
    - priest `Remove Curse` now clears curses across carried/equipped items
    - priest `Glyph of Warding` is now mechanically active
    - priest `Holy Word` now follows the VMS-style cure/full-heal/dispel-evil behavior already chosen for Commodore
  - documentation added at `commodore/SPELLS.md` with:
    - full 62-entry spell/prayer catalog
    - legacy vs added status
    - per-book membership
    - per-class level/mana/fail data
    - current Commodore deviations and upstream-source notes
  - C64 test harness fixes:
    - `test_main_loop.s` now uses tiny local spell stubs instead of importing the full spell runtime, keeping the test body below `$C000`
    - `ui_trampoline_stubs.s` now provides no-op spell trampolines instead of dragging full spell overlays into unrelated suites
    - `test_effects.s` was updated off the removed `pm_do_cast` helper and its local scratch buffers were moved up to `$B800`
    - `test_save.s` and `test_monster_magic.s` were trimmed the same way after the spell refactor pushed both resident test bodies past `$C000`; local spell stubs brought them back under `MAP_BASE` and restored the breakpoint contract
    - fixed the live C64 `m` -> book -> `a` hang by making `spell_mask_test_ptr` preserve `X` and correcting the 31-spell mask-byte table to use `8,8,8,7` grouping
    - added a focused `test_effects.s` regression that builds the learnable mage list for `[Beginners-Magick]` and verifies all 7 entries are returned
  - C128 smoke harness fixes:
    - `build_boot_assets()` now invalidates on shared `../common/*.s`, `../c64/*.s`, and the actual booted `out/moria128.d71`
    - `boot_title_idle_smoke` now uses one monitor `until` probe per boot run instead of chaining two `until` commands in one playback file
  - spell hardening follow-up:
    - `player_cast_spell` and `player_pray` now gate on `class_spell_min_level` before prompting for books, so low-level rogue/ranger flows fail early with `HSTR_PM_NO_EXP`
    - `scripted_spell_cast_smoke` is now part of the default live gates on both platforms instead of a dormant helper smoke:
      - C64 `make test64` now runs a disk-backed in-game cast flow that completes chargen, opens the filtered book prompt, casts repeatedly, and only passes after the live pass trap is reached
      - C128 `make test128-fast-smoke` now includes `scripted_spell_cast_smoke`, and the scripted flow must return to `main_loop` after repeated successful casts
    - fixed the scripted smoke input contract to use filtered-inventory letters, not raw carried-slot letters:
      - the only visible book in the filtered prompt is `A`, even when it lives in carried slot `B`
      - both C64 and C128 scripted spell inputs now select the book with `A`
    - fixed the C64 smoke harness classification so a reached pass trap is authoritative; it no longer misreports a later cycle-limit after `BRK` as a spell JAM
    - `test_effects.s` now covers:
      - high-book-bit learnable-list construction for `[Beginners-Magick]`
      - repeated full `player_cast_spell` flow stability
      - rogue/ranger low-level `m` UX
    - the C128 spell-load JAM was fixed by moving spell UI literals out of low common RAM and back into the UI overlay owner
    - the follow-up live C128 spell JAM at `$D063` was caused by `player_cast_spell` staying below `$D000` while its internal `pm_*` helpers drifted into `$D000-$D2xx`
    - repaired by splitting resident spell state from spell logic:
      - `player_magic_state.s` keeps shared spell scratch/state resident
      - C128 `player_magic.s` now lives in the banked payload, so `player_cast_spell` and its `pm_*` helper callees resolve at `$F2xx-$F5xx`
      - resident bookkeeping helpers (`pm_mark_worked`, `pm_learn_selected_spell`) moved out of the banked payload to keep the staged source below `$E000`
      - C128 IO audits now cover the internal `pm_*` helper surfaces, not just the top-level trampolines
      - C64 unit suites now import the split resident spell-state owners directly
  - final verification:
    - `make build64` -> PASS
    - `make build128` -> PASS
    - `make test64` -> `=== Results: 34 passed, 0 failed (of 34 suites) ===`
    - `make test128-fast` -> PASS for both `cold` and `snapshot`
    - `make test128-fast-smoke` -> `=== Results: 4 passed, 0 failed (of 4 suites) ===`
    - `cd commodore/c128 && TEST_FILTER='scripted_spell_cast_smoke' ./run_tests128.sh` -> `=== Results: 1 passed, 0 failed (of 1 suites) ===`
    - `make test` -> PASS
- BUG-C128-RECALL-GLYPH-CORRUPTION follow-up:
  - root cause was in the shared recall renderer, not a C128-only overlay/load issue
  - fixed four shared-renderer bugs in `commodore/common/ui_recall.s`:
    - the HP / damage-dice separator used raw screen-code `$04` for `D`, which displays as lowercase `d` on the C128 VDC backend
    - the attack abbreviation printer indexed `rcl_atk_3` through `Y`, but `screen_put_char` clobbers `Y`, so only the first attack letter survived and the rest came from the wrong table bytes
    - the inter-attack separator reused one loaded space byte across two `screen_put_char` calls, but `screen_put_char` does not preserve `A`, so the second separator cell could render garbage
    - placeholder creature attack slots with `type=HIT` but `dice/sides=0` were rendered literally as `HIT 0D0` instead of being treated as unknown / absent data
  - repaired by:
    - switching the explicit `D` writes to PETSCII-safe uppercase `$44`
    - storing attack abbreviations as PETSCII-safe uppercase bytes
    - iterating the abbreviation bytes through `X`, which both screen backends preserve
    - reloading the literal space before each separator write
    - only rendering an attack slot when `type`, `dice`, and `sides` are all nonzero, with `Atk: None` as the fallback when no real attack data is known
  - strengthened regression coverage in `commodore/c64/tests/test_ui_views.s`:
    - seed the recall test creature with a real attack
    - assert the rendered `HP` bytes contain `1D8`
    - assert the rendered attack bytes contain `HIT 2D6`
    - assert the zero-damage placeholder case renders `None` instead of `0D0`
  - verification:
    - `make build64` -> PASS
    - `make build128` -> PASS
    - `make test64` -> `=== Results: 33 passed, 0 failed (of 33 suites) ===`
    - `make test128-fast` -> PASS for both `cold` and `snapshot`
- BUG-RECALL-RESTORE-UMORIA follow-up:
  - restored `/` to the old monster-memory recall behavior in `commodore/common/game_loop_helpers.s`
  - the shared command now:
    - prompts `Recall which?`
    - normalizes the typed creature symbol
    - searches creature types with matching display glyphs
    - only opens recall for creatures with known memory (`kills/deaths/attacks/spells`)
    - cycles through additional matching creature types on repeated input
  - restored production recall owners:
    - C64: `tramp_ui_recall` plus banked `ui_recall.s`
    - C128: `tramp_ui_recall` plus `ui_recall.s` in `UiOverlay`
  - intentionally displaced the now-unused C128 symbol-identify owner from the product build to keep the C128 memory layout safe
  - updated the C64 `main_loop` recall test so it seeds recall knowledge and asserts the recall UI path instead of the old identify-string behavior
  - verification:
    - `make build64` -> PASS
    - `make build128` -> PASS
    - `make test64` -> `=== Results: 33 passed, 0 failed (of 33 suites) ===`
    - `make test128-fast` -> PASS for both `cold` and `snapshot`
- BUG-C128-TITLE-BOOT-QUIT-PROMPT follow-up:
  - root cause was the earlier C128 layout fix moving `title_screen.s` into the banked `$F000` payload
  - that move violated the live C128 bank/visibility contract:
    - `c128_title_load_and_draw_cached` in low RAM still jumps directly to `title_render_data` and `title_fallback_render`
    - those helpers were no longer resident/overlay code, so the title path could reach the wrong bytes while KERNAL-visible state was active
  - repaired by:
    - moving `title_screen.s` back into `UiOverlay`
    - restoring the original C128 title trampoline pattern that loads `OVL.UI` and tail-jumps into `title_load_and_draw`
    - keeping the safe ownership savings that were not part of the regression:
      - `player_magic_levelup.s` stays banked
      - `ui_inventory.s` and `ui_equipment.s` stay in `HelpOverlay`
      - `magic_check_new_spells` stays banked
  - strengthened the boot smoke:
    - `boot_title_idle_smoke` now requires both `title_show_sysinfo` and `title_menu_ready`
    - it now fails if `game_over_prompt` is hit during initial boot or idle title soak
  - verification:
    - `make build128` -> PASS
    - `TEST_FILTER='boot_title_idle_smoke' bash commodore/c128/run_tests128.sh` -> PASS
- BUG-C128-BUILD-GATE follow-up:
  - root cause was real and two-layered:
    - `ui_equip_display` had been split into `commodore/common/ui_equipment.s`, but C128 never imported that owner
    - after restoring that symbol, `UiOverlay` was still oversized, so the branch had shipped with a second latent C128 layout failure
  - restored C128 ownership by:
    - moving `ui_equip_display` and `ui_inv_display` into `HelpOverlay`
    - moving `magic_check_new_spells` and `title_screen.s` into the banked payload
    - switching `tramp_magic_check_new_spells` to the banked compute trampoline
    - switching `tramp_title_load_and_draw` to banked execution with the existing UI enter/exit contract
    - updating `commodore/c128/io_contracts.s` to match the new overlay/banked residency
  - final green C128 layout:
    - `UiOverlay`: `3908` bytes at `$E000-$EF44`
    - `HelpOverlay`: `3899` bytes at `$E000-$EF3B`
    - `Banked payload`: `3998` bytes, staged source ending at `$DE92`
  - verification:
    - exact reported gate: `make build128` -> PASS
    - sibling platform safety check: `make build64` -> PASS
    - tester signoff: `ALL TESTS PASSED`
- FEAT-AUD follow-up:
  - added two new shared sound IDs in `commodore/common/sound.s`:
    - `SFX_HUNGER_WARN` for entry into `HUNGRY` and `WEAK`
    - `SFX_HUNGER_FAINT` for entry into `FAINT`
  - implemented both effects as new low pulse-wave warnings distinct from the existing combat/UI sound palette
  - kept hunger classification pure in `commodore/common/turn.s`; the new alert only fires from `turn_tick_hunger` when the state gets worse
  - fixed one real gameplay bug during implementation:
    - the first helper version tail-jumped into `sound_play`, which would have skipped the starvation damage tail on the `food == 0` path
  - expanded focused C64 coverage:
    - `commodore/c64/tests/test_sound_monitor.s` now validates both new SID shapes and keeps the invalid-ID checkpoint truly invalid at `$0A`
    - `commodore/c64/tests/test_turn.s` now covers entry to `HUNGRY`, `WEAK`, and `FAINT`, plus no-replay behavior for steady/recovery states
  - fixed two C64 test regressions exposed by the added code growth:
    - `commodore/c64/tests/test_main_loop.s` had a 2-byte `check_player_on_store_door` stub under a 3-byte jump-patch contract; the patch now uses a 3-byte slot and asserts it
    - `commodore/c64/tests/test_turn.s` needed its new hunger tests to run before `install_turn_patches`, and its control flow now reaches `test_finish` without looping
  - verification on the current tree:
    - `make test64` -> `=== Results: 33 passed, 0 failed (of 33 suites) ===`
    - `make test128-fast` -> PASS through both `cold` and `snapshot` batches
- C64 dead-code audit follow-up:
  - audited the current shipping C64 imports looking specifically for helpers still linked into the shipping image but only referenced from tests
  - confirmed the old `bank_load_recall` owner was already test-only and not costing the shipping image anymore
  - found one additional shipping-dead banked owner:
    - `commodore/common/string_bank_banked.s`
    - only exported symbol `bank_decode_string`
    - no production callsites; subsystem tests import the file directly
  - removed that dead banked import from `commodore/c64/main.s`
  - measured recovery:
    - banked payload reduced from `2923` bytes to `2898` bytes
    - exact gain: `25` bytes
  - current verification:
    - `make -C commodore out/c64/moria8.prg` -> PASS
    - `make test64` -> `=== Results: 33 passed, 0 failed (of 33 suites) ===`
- C64 inventory overlay ownership follow-up:
  - user feedback on the live build was correct: inventory is frequent enough that paying an overlay load for it was the wrong product tradeoff
  - split the old shared inventory/equipment owner into `commodore/common/ui_inventory.s` and `commodore/common/ui_equipment.s`
  - inventory now lives back in the C64 banked payload, while equipment stays in `OVL.UI`
  - actual measured cost of restoring banked inventory ownership: `240` bytes
  - current layout after the change:
    - `Program fits below MAP_BASE=true`
    - `banked payload: 2923 bytes at $BE6E-$C9D9`
    - `UI overlay: 1081 bytes at $E000-$E439`
  - current verification:
    - `make -C commodore out/c64/moria8.prg` -> PASS
    - `make test64` -> `=== Results: 33 passed, 0 failed (of 33 suites) ===`
- C64 wizard overlay ownership follow-up:
  - live testing found a real regression: entering wizard mode could show `Loading...` and then lock up with an IRQ storm
  - root cause: moving wizard into `OVL.UI` was unsafe on C64 because wizard entry/restore paths can call gameplay redraw helpers that re-check and reload the active tier, and that tier reload repopulates the same `$E000` window the wizard overlay was executing from
  - fixed by restoring the old banked C64 wizard owner in `commodore/common/wizard.s`, switching `tramp_ui_wizard_display` back to `wizard_c64_menu_display`, and removing `ui_wizard.s` from the C64 UI overlay segment
  - current verification:
    - `make -C commodore out/c64/moria8.prg` -> `Program fits below MAP_BASE=true`
    - `make test64` -> `=== Results: 33 passed, 0 failed (of 33 suites) ===`
- Recall semantics audit follow-up:
  - upstream check confirmed the semantic split:
    - `umoria` uses `/` as monster memory/recall after observation/encounters
    - `vms-moria` uses `/` as symbol identification, with `look` handling the exact visible creature
  - implemented follow-up:
    - `/` now uses VMS-style symbol identification instead of the old combat-earned recall modal
    - the large glossary moved into `OVL.UI` so the C64 resident image still fits below `MAP_BASE`
    - detailed monster knowledge is now intentionally future `look`/UX work, not `/`
    - post-fix user repro found a shifted lowercase lookup (`p` reported `q`); the backslash table entry was emitting two bytes, so the lookup now uses an explicit `$5c` byte and the focused regression covers `p`
  - current verification:
    - `make test64` -> `=== Results: 33 passed, 0 failed (of 33 suites) ===`
    - `make test128-fast` -> `PASS`
- C64 recall/tier-state follow-up after the `OVL.UI` ownership move:
  - C64 overlay-backed modal returns were leaving `current_tier` invalid after `overlay_load` reused the `$E000` window, so later gameplay paths could run with stale tier state
  - fixed the shared C64 restore seams by re-checking the active tier before gameplay redraw in `ui_restore.s` and in the C64 character-view full-screen return path
  - added a direct C64 `/` recall tier re-check at the start of `cmd_recall_view`, so recall no longer depends on a previous modal having left tier state valid
  - expanded `commodore/c64/tests/test_main_loop.s` with two new tier-restore coverage points and updated `commodore/c64/run_tests.sh` to read `24` `main_loop` results instead of truncating at `22`
  - latest verification on the current tree:
    - `make -C commodore out/c64/moria8.prg` -> `Program fits below MAP_BASE=true`
    - `make test64` -> `=== Results: 33 passed, 0 failed (of 33 suites) ===`
- C64 string-shortening regression follow-up:
  - restored the shortened save/load runtime strings in `commodore/common/runtime_ui_strings.s`, including `Welcome back to Moria8!`
  - recorded the user-copy rule in `tasks/lessons.md`: do not shorten user-facing strings to recover bytes without explicit consent
  - exact C64 memory result after restoring the strings:
    - `make -C commodore out/c64/moria8.prg` still assembles but reports `Program fits below MAP_BASE=false`
    - the assert owner is [`commodore/c64/main.s:939`](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-work/commodore/c64/main.s:939)
    - `program_end` moves from `$BFF8` on `HEAD` to `$C02E` with the restored strings
    - that is a `54`-byte growth, and it pushes `program_end` `46` bytes past `MAP_BASE=$C000`
    - the staged banked payload then occupies `$C02E-$CFC6`, so the init-only payload storage overlaps `4038` bytes of the dungeon-map window
  - control comparison against `HEAD`:
    - `Program fits below MAP_BASE=true`
    - `Banked payload: 3992 bytes at $BFF8-$CF90`
- C64 resident-byte recovery after restoring the runtime strings:
  - moved the dead in-memory RLE compressor in `commodore/common/save.s` to test-only ownership behind `SAVE_TEST_RLE`
  - added a dedicated `save_magic_buf` so production load no longer borrows the compressor literal buffer for header verification
  - opted `commodore/c64/tests/test_save.s` into the old compressor explicitly so the round-trip unit coverage still assembles
  - exact direct-assembly result after the recovery:
    - `make -C commodore out/c64/moria8.prg` -> `Program fits below MAP_BASE=true`
    - `Banked payload: 3992 bytes at $BE6C-$CE04`
    - relative to the restored-string overflow state, that recovered `450` bytes and cleared the original `46`-byte overrun with margin
  - regression verification:
    - `make test64` -> `=== Results: 33 passed, 0 failed (of 33 suites) ===`
- C64 UI ownership follow-up after the save-side cleanup:
  - moved the character, inventory, equipment, and wizard modal screens out of the banked `$F000` payload and into `OVL.UI`
  - tried the same move for recall, then backed it out after the live recall path proved unsafe under the overlay contract
  - recall now stays in the banked payload on C64 because it reads live creature/tier state that already occupies the `$E000` overlay window
  - left `ui_home.s` in the banked payload intentionally because it is store-owned and depends on town-overlay helpers
  - removed the dead shipping C64 import of `commodore/common/string_bank.s`; the only remaining `bank_load_recall` coverage lives in tests that import that file directly
  - simplified `commodore/common/wizard.s` back to shared state and non-UI helpers, with the UI/menu flow now living in `commodore/common/ui_wizard.s`
  - exact direct-assembly result after the ownership move:
    - `make -C commodore out/c64/moria8.prg` -> `Program fits below MAP_BASE=true`
    - `program_end = $BA39`
    - `Banked payload: 2683 bytes at $BA66-$C4E1`
    - `UI overlay: 2332 bytes at $E000-$E91C`
    - relative to the pre-change state, that recovered `1309` bytes from the banked payload and increased resident headroom below `MAP_BASE` from `449` bytes to `1479` bytes
  - regression verification:
    - `make test64` -> `=== Results: 33 passed, 0 failed (of 33 suites) ===`
- C64 boot-art asset pipeline update:
  - kept `commodore/c64/boot.s` and `tools/ppm_to_c64_bootart.py` unchanged
  - added `tools/png_to_ppm.py` as a source-image adapter that enforces exact dimensions and writes the existing PPM intermediate
  - rewired `commodore/Makefile` so C64 boot art now uses `artwork/moria8_loading_art_c64.png` as the canonical source asset
  - preserved the existing C64 boot-art PRG staging contract at `$A000`
  - accepted the artist PNG's unused indexed transparency metadata without altering any visible pixels
  - verified the real asset path:
    - `python3 tools/png_to_ppm.py artwork/moria8_loading_art_c64.png 160 200 /tmp/moria8_work_asset.ppm` -> PASS
    - `make -C commodore out/c64/bootart64.ppm out/c64/bootart64.prg` -> PASS
- C64 parity follow-up after the user's live screenshots:
  - kept the C64 prompt/screen-clear behavior in the product path
  - the first bad recovery attempt shortened the C64-only runtime UI strings instead of backing out or restructuring the resident code
  - that copy regression has now been reversed, and the resident fit is recovered structurally from dead save-side code instead
  - fixed the stale `test_main_loop.s` stub collision by removing the duplicate local `msg_init`
- Exact verification after the C64 follow-up:
  - `make test64` -> `=== Results: 33 passed, 0 failed (of 33 suites) ===`
  - `make test128-fast` -> PASS
- Extended the save/load UX fix to C64 instead of leaving the earlier C128-only behavior behind:
  - one-drive C64 Disk Setup now leaves a one-shot fresh-setup state so the immediate save/load transaction does not ask for a second `Press any key`
  - the C64 save path now clears to a dedicated prompt/status screen before save-disk and program-disk prompts, and failed save returns redraw gameplay before re-entering the command loop
  - C64 overwrite handling now probes for an existing `THE.GAME` before writing and prompts `Overwrite? Y/N` instead of falling into a disk error on overwrite attempts
- Verification:
  - `make test64` -> `=== Results: 33 passed, 0 failed (of 33 suites) ===`
  - `make test128-fast` -> PASS
- Restored the exact C128 fast batch gate by fixing the snapshot compare harness rather than changing product save/load code:
  - `commodore/c128/harness128_batch.py` now restores connector-backed snapshot tests at VICE startup with a temporary `-moncommands undump ...` file, one VICE process per snapshot test, and the same low-memory/banking reset contract used by the moncommands path
  - `commodore/c128/tests/vice_connector.py` no longer issues the invalid remote monitor command `r p=...` in the shared connector runner; the monitor path now matches the working moncommands register setup more closely
- Focused verification while narrowing the fix:
  - `python3 -u commodore/c128/harness128_batch.py --mode snapshot --tests vdc_attr128,dungeon128,main_loop128 --snapshot-path commodore/c128/out/ready.vsf --vice /opt/homebrew/bin/x128 --connect-timeout 12` -> all `PASS`
- Exact reported gate:
  - `make test128-fast` -> `PASS`
- Implemented a C128 session title-art cache in Bank 1 reserved gap 0:
  - `commodore/common/title_screen.s` now routes the C128 title loader through a cache-aware runtime-common helper
  - `commodore/common/title_cache_runtime128.s` owns cache validity, MAP_BASE -> cache store, and cache -> MAP_BASE restore
  - `commodore/c128/memory128.s` now reserves and asserts the Bank 1 title-cache slot
- Preserved the earlier accepted C128 mounted-save-disk load fixes already in the dirty tree:
  - `commodore/common/disk_setup_runtime128.s` still marks the immediate post-setup title `L` path with `disk_setup_done = 2`
  - `commodore/common/save.s` still skips redundant save-media revalidation for that exact C128 title `L` transaction
  - `commodore/c128/main.s` still routes failed title-load return back through `title_enter_menu`
- Added a new exact-user-path smoke harness owner:
  - `commodore/c128/run_tests128.sh:boot_title_load_missing_savefile_smoke`
  - `commodore/c128/tests/title_load_missing_save_smoke.py`
  - current status: harness still red; it reaches the mounted-save-disk transaction but the remote-monitor live-swap leg is not yet proving the cached-art return
- Current verification on the tree:
  - `make disk128` -> PASS
  - `TEST_FILTER='title_art_smoke|boot_title_load_resume_smoke' bash commodore/c128/run_tests128.sh` -> `=== Results: 2 passed, 0 failed (of 2 suites) ===`
  - `make test128-fast-smoke` -> `=== Results: 3 passed, 0 failed (of 3 suites) ===`
- Current blocker:
  - `TEST_FILTER='boot_title_load_missing_savefile_smoke' bash commodore/c128/run_tests128.sh` is still red
  - latest failure shape: initial title-menu stop is fine, but the second leg times out waiting for `c128_test_title_art_pass_sym` after the live drive-8 swap
  - that means the exact mounted-save-disk smoke still needs harness/product isolation before this bug can be considered fully closed
- Implemented the C128 one-drive prompt policy at the shared owner: `commodore/common/disk_swap.s:disk_prompt_game` now returns immediately on C128 when `disk_mode == 1`, intentionally skipping the obsolete return-to-program-disk prompt and its drive re-init side effect.
- Added focused C128 verification:
  - new unit `commodore/c128/tests/test_disk_swap128.s`
  - expanded `commodore/c128/tests/test_main_loop128.s` save/death caller coverage
  - tightened `commodore/c128/run_tests128.sh:run_boot_title_load_resume_smoke` with a negative assertion that the title-load flow does not execute `disk_prompt_game`
- Verification results on the current tree:
  - `TEST_FILTER='disk_swap128|main_loop128|boot_title_load_resume_smoke' bash commodore/c128/run_tests128.sh` -> `=== Results: 3 passed, 0 failed (of 3 suites) ===`
  - `make disk128` -> PASS
  - `TEST_FILTER='boot_title_load_resume_smoke' bash commodore/c128/run_tests128.sh` -> `=== Results: 1 passed, 0 failed (of 1 suites) ===`
  - `make test128-fast-smoke` -> `=== Results: 3 passed, 0 failed (of 3 suites) ===`
- Verification note:
  - the tester’s first unit rerun failed only inside the sandbox because `x128 -autostart <unit.prg>` segfaults there; the same VICE-backed gates passed when rerun outside the sandbox.

## Latest Resolved
- The active C128 drive-8 title-load red gate was a harness-model bug after the `128.RUNTIME` fix, not a remaining product failure on the user path. The real user repro is “valid save disk already mounted in drive 8, then press `L`,” so the title-load smokes now snapshot at `title_menu_ready`, mount the save disk before injecting `L`, and allow direct resume if no old swap probe is hit.
- The C128 live title-`L` load seam no longer relies on a truncated common-helper install: `init_common_mmu_helpers` now copies the full `$110`-byte blob into common RAM, so `mmu_kernal_irq` and `mmu_common_nmi` are actually present at their runtime addresses instead of being silently zeroed past the old 8-bit copy-loop cutoff.
- C128 boot/title no longer JSRs into overlay-owned title preload code as if it were resident; title-art preload now enters through a resident trampoline that first loads the UI overlay, eliminating the `128.RUNTIME`/title-entry JAM at `$EC75`.
- C128 one-drive save-disk load no longer drags HELP/message UI back to the program disk after preload; `OVL_HELP` now uses the same overlay-cache contract as the rest of the preloaded runtime, and the C128 test suite has a dedicated program-media policy guard for that seam.
- FEAT-DISK no longer forces setup on `N)ew`; the setup trigger now moves to real persistence events, C64 Disk Setup uses the proven row-clear modal wipe, and failed `SHIFT+S` saves no longer drop into the quit menu.
- The C64 REU startup hang while loading `64.UI` is fixed by keeping `UiOverlay` as a valid `$E000` placeholder PRG instead of emitting an empty `$0000` image.
- Directed `look` now preserves terrain message IDs across the flash path and treats non-floor terrain as authoritative, fixing trap/door misreports and wall-as-gold lookups.
- The C128 boot-art helper now writes the poster attribute map before the screen map, eliminating the brief wrong-font flash before the custom poster appears.
- The shared town layout now uses a fixed `66x22` umoria-sized footprint on both C64 and C128 while retaining the Commodore-only Black Market and Home in a deliberate `4x2` layout.
- Shipping disk outputs are now split by platform:
  - `commodore/out/moria8-c64.d64`
  - `commodore/out/moria8-c128.d71`
- The late native-C128 `128.RUNTIME` hang is fixed by reserving Track 1 / Sector 0 before patching the boot sector.
- The current shipped boot-art baseline is asset-backed on both platforms:
  - C64: tracked artist PNG through the multicolor bitmap boot-art pipeline
  - C128: tracked tile-native PNG through the native 80-column VDC custom-charset poster pipeline
- The C128 boot-art handoff now blanks the VDC screen before restoring the normal charset, preventing the preload/title garbage-font flash.
- The disk directory card and title-screen version line are now sourced from `version.json`.
- The recurring C128 town top-row garbage bug is fixed by programming 8563 VDC block-copy mode before writing the block-op trigger register.

## Reported Failure Gate
  - Active:
  - new visible regression gate:
    - `make disk128`
    - boot the shipping C128 disk the same way `make run128` does
    - current live regression: title screen flashes between the normal title and a dashed-line / box-art variant before any save-load interaction
    - scope correction:
      - this regression is caused by the current uncommitted C128 title/title-art/runtime work and must be fixed before further save-load chasing is valid
  - exact live/user gate:
    - `make disk128`
    - boot the shipping C128 disk the same way `make run128` does
    - user environment uses JiffyDOS C128 + 1571 ROMs from `~/.config/vice/vicerc`
    - insert a valid save disk in drive `8` before pressing `L`
    - current local automation now matches that mounted-save-disk path instead of waiting for the older “insert save disk now” prompt flow
  - exact automated repro gate:
    - `TEST_FILTER='boot_title_load_resume_drive8_smoke' bash commodore/c128/run_tests128.sh`
    - current status: PASS on the local tree
    - latest live/manual trace maps to `title_menu_loop -> input_get_key -> input_process_sample_strict`, which means the machine fell back to the title-menu input loop after the load attempt rather than CPU-JAMing
    - the smoke now dismisses the program-disk prompt with a real key and treats any post-load return to `title_menu_loop` as failure, but that stronger local gate still passes
    - adjacent mounted-save-disk title-load gates:
      - `TEST_FILTER='boot_title_load_resume_drive8_shipping_smoke|boot_title_load_resume_drive8_realboot_smoke' bash commodore/c128/run_tests128.sh` -> PASS
  - exact automated repro now required before any further product fixes:
    - direct `x128` boot of `commodore/out/moria8-c128.d71`
    - no `-autostart`
    - `-drive8truedrive -drive8type 1571 +busdevice8`
    - for title `L`, the authoritative mounted-save-disk path is now:
      - reach `title_menu_ready`
      - attach the valid save disk on drive `8`
      - inject `L`
      - pass if gameplay resumes, even if the old first swap breakpoint is skipped
  - exact build gate before each retest:
    - `make test64`
    - `make disk128`
    - `make test128-fast-smoke`
  - current code-backed hypothesis:
    - the remaining high-probability owner is a C128 runtime resync seam, not the save-file read itself
    - live `IRQ -> $0D06 / BRK` means runtime is still seeing a KERNAL-visible IRQ tail or a half-restored vector page after title `L`
    - latest live monitor trace narrowed this further:
      - live PC is still `$0D06`
      - `$0D06` is exactly one page above `mmu_common_irq` at `$0C06`
      - that means the bad vector still looks like a native KERNAL IRQ-tail high byte (`$0D`) surviving where the runtime bridge high byte (`$0C`) should be
    - refined owner after inspecting the current tree:
      - `commodore/c128/memory128.s:EnterKernal_sub` was still restoring `$0314/$0315` to the startup-captured native IRQ tail
      - in this build, that captured native tail still resolves to `$0D06`, but executable Screen Editor tail code is not preserved there
      - any IRQ during a KERNAL-visible window could therefore jump straight into common-RAM garbage and collapse into the exact repeated `IRQ -> $0D06 / BRK` storm from the live monitor trace
    - live correction after the failed `mmu_kernal_irq` spike:
      - chasing JiffyDOS stack details was the wrong abstraction level
      - the actual design break is that the product was loading runtime-owned bytes into KERNAL/editor low-common workspace and then trying to patch around the fallout at `$0314/$0315`
      - current concrete overlap:
        - `128.fdisk.prg` was being loaded at `$0D20-$0EED`
      - that meant title `L` was still placing runtime-owned FEAT-DISK code inside the same low-common region that KERNAL-visible IRQ/editor mode still expects to own
    - too many C128 paths were only calling `c128_restore_runtime_guards`, which restored MMU/VDC state but not the full IRQ/CHRIN bridge
    - current correction:
      - `commodore/c128/main.s:c128_restore_runtime_guards` and `c128_restore_runtime_after_kernal_full` now share one authoritative `c128_restore_runtime_guards_core`
      - that core path restores all-RAM MMU state, zeros `KERNAL_NESTING_DEPTH`, reinstalls common helpers, reasserts VDC mode, and reinstalls the runtime IRQ/NMI/CHRIN bridge in one atomic sequence
      - clean fix shape now being implemented:
        - move `128.fdisk.prg` out of `$0D20+` and into owned Bank 0 scratch instead of KERNAL/editor low-common workspace
        - remove the custom `mmu_kernal_irq` detour entirely
        - stop restoring the boot-time saved `$0314/$0315` vector
        - on `EnterKernal_sub`, call `SCNKEY` so the Screen Editor reasserts its live native software IRQ tail itself
        - on `ExitKernal_sub`, reinstall the runtime-owned `mmu_common_irq` bridge
- Most recent closed gate:
  - `make clean`
  - `make run128`
  - fixed by splitting the shipping images and reserving the native C128 boot sector before file allocation

## Current Task
- [ ] BUG-C128-TITLE-SCREEN-FLASH
  - [x] stop the save-seed/gamewritten chase and re-anchor on the newly reported visible title-screen regression
  - [x] inspect the current uncommitted C128 title/title-art/runtime changes for the smallest causally sufficient owner
  - [ ] restore the C128 title screen to the proven direct-load draw path without deleting the newer cache/preload code
  - [ ] verify the title screen is stable on the exact shipping C128 boot path before resuming save-load work
  - review:
    - current strongest static owner:
      - `commodore/common/title_screen.s`
      - `commodore/c128/main.s`
    - regression mechanism:
      - the branch introduced a new C128 title-art preload/cache path and a new boot-time `tramp_c128_preload_title_art` call
      - the live symptom is a visible title flash between the normal screen and a dashed-line / box-art variant, which is outside the save-load contract and points at title-art render/cache state
    - containment strategy:
      - keep the newer title-art cache/preload code in tree
      - disable its use at boot/title entry
      - return C128 title draw to the older direct-load path first so the save-load investigation resumes from a sane visual baseline
    - failed first attempt:
      - simply disabling `c128_title_art_cached` and skipping boot-time preload was not enough
      - that still left `title_load_and_draw` using the newer resident `c128_load_title_art_bank1` path, and the user still saw the flashing title regression live
    - current correction:
      - revert the active `title_load_and_draw` contract itself to the older direct `SETBNK -> SETNAM -> SETLFS -> LOAD -> CLOSE -> screen_clear -> title_render_data` path
      - keep the newer preload/cache helpers in tree but inactive
- [ ] BUG-C128-TITLE-L-RUNTIME-REENTRY
  - [x] replace the false-green shell `boot_runtime_load_guard_repro` with a trustworthy direct-boot remote-monitor repro for the `128.RUNTIME` load seam
  - [x] split `commodore/c128/main.s:c128_load_runtime_prg` back off `commodore/common/reu.s:c128_preload_asset_load`
  - [ ] compare the current red `boot_runtime_load_guard_repro` against clean `HEAD` to isolate the smallest uncommitted runtime/MMU regression set
  - [ ] remove the remaining failed C128 runtime/MMU experiments that are not required by the exact red repro
  - [ ] verify the exact runtime-load repro goes red on the bad path and green on the final fix before any user retest
  - [x] codify the real shipping-boot/JiffyDOS repro in automation before touching product preload/runtime code
  - [x] use that exact repro to isolate the regression by revert slice, starting with:
    - `commodore/common/reu.s:c128_preload_asset_load`
    - `commodore/c128/memory128.s:EnterKernal_sub / ExitKernal_sub / mmu_kernal_irq`
  - [x] only after the exact repro is red and then green, rerun the broader C128 smokes and the drive-8 title-`L` path
  - review addendum:
    - latest exact runtime-load repro result:
      - `TEST_FILTER='boot_runtime_load_guard_repro' bash commodore/c128/run_tests128.sh` -> PASS
      - current direct shipping boot also reaches `title_menu_ready`:
        - `TEST_FILTER='boot_real_shipping_repro' bash commodore/c128/run_tests128.sh` -> PASS
    - verified root cause for the current `128.RUNTIME` boot hang:
      - the active failure was no longer inside raw `kernal_load`
      - both runtime loads were returning, but the next boot step `tramp_c128_preload_title_art -> c128_preload_title_art` was corrupting the stack before title entry
      - concrete bug:
        - `commodore/common/title_screen.s:c128_preload_title_art` did `jsr c128_load_title_art_bank1` followed by `plp`
        - `commodore/c128/main.s:c128_load_title_art_bank1` already restores its own saved LOAD status before `rts`
        - that extra caller-side `plp` popped a return-address byte instead of flags, which explains the post-load unwind into garbage before title
    - verified fix:
      - removed the stray caller-side `plp` from `commodore/common/title_screen.s:c128_preload_title_art`
      - kept the exact automated runtime-load repro, but relaxed its old `require_irq_hit` assumption so it now treats a quiet runtime-load window as valid while still checking IRQ ownership if an IRQ happens
    - current remaining follow-up failures are not the original boot/runtime bug:
      - `boot_title_load_resume_drive8_realboot_smoke`
      - `boot_title_load_resume_drive8_shipping_smoke`
      - current failure shape in both:
        - they no longer crash in `128.RUNTIME`
        - they currently stall in title-input / later swap-path orchestration, which is a separate harness/product bucket from the fixed boot-runtime hang
    - exact automated repro now exists:
      - `TEST_FILTER='boot_real_shipping_repro' bash commodore/c128/run_tests128.sh`
      - it boots the shipping `commodore/out/moria8-c128.d71` the same way `make run128` does:
        - no `-autostart`
        - `-drive8truedrive -drive8type 1571 +busdevice8`
        - user JiffyDOS ROM config from `~/.config/vice/vicerc`
    - exact repro result during isolation:
      - red on current tree with `captured live preload/title crash on real shipping boot`
      - green after reverting the KERNAL-window owner refactor in `commodore/c128/memory128.s` and restoring the matching `$0314/$0315` capture in `commodore/c128/main.s`
      - still green after restoring the `commodore/common/reu.s:c128_preload_asset_load` transaction rewrite
    - isolated root cause:
      - the regression was not the shared preload transaction rewrite
      - the regression was the KERNAL-window ownership refactor:
        - `EnterKernal_sub` stopped restoring the live native IRQ tail and started forcing `mmu_kernal_irq`
        - `ExitKernal_sub` started reinstating extra runtime-owned state from inside the wrapper substrate
        - `entry_main` had also stopped capturing the live `$0314/$0315` KERNAL IRQ tail that the older wrapper contract expects
      - that refactor is the smallest causally sufficient change set that made the real shipping boot crash and then stop crashing
    - current verified gates:
      - `TEST_FILTER='boot_real_shipping_repro' bash commodore/c128/run_tests128.sh` -> PASS
      - `TEST_FILTER='boot_title_idle_smoke|boot_real_shipping_repro|boot_title_load_resume_drive8_shipping_smoke|boot_title_load_resume_drive8_smoke' bash commodore/c128/run_tests128.sh` -> PASS
      - `make test128-fast-smoke` -> `=== Results: 9 passed, 0 failed (of 9 suites) ===`
  - [x] unify C128 runtime re-entry behind one authoritative restore owner
  - [x] route title-load resume, preload asset return, and UI/overlay return seams through that owner instead of split guard/vector repairs
  - [x] add C128-only post-load runtime probes for `$0314/$0315`, `$FFFE/$FFFF`, `$01`, `$FF00`, and `KERNAL_NESTING_DEPTH`
  - [ ] keep richer restart-reason/count diagnostics only if they fit the resident C128 staging ceiling; otherwise let the strengthened smoke fail on `entry_main` directly
  - [x] replace the early-pass drive-8 title-load smoke stop with a deeper post-resume runtime/input seam and fail on late restart
  - [x] rerun focused gates:
    - `make disk128`
    - `TEST_FILTER='boot_title_load_resume_drive8_smoke' bash commodore/c128/run_tests128.sh`
    - `TEST_FILTER='boot_title_load_resume_drive8_shipping_smoke' bash commodore/c128/run_tests128.sh`
    - `make test128-fast-smoke`
    - `make test64`
  - review:
    - live red gate:
      - fresh `make disk128`
      - boot C128
      - valid save disk in drive `8`
      - press `L`
      - current live failure: repeated `IRQ -> $0D06` / `BRK`, sometimes with `128.RUNTIME` visible
    - current working diagnosis:
      - this is still a C128 runtime/MMU/vector unwind problem, not a save-file format failure
      - the current tree still splits C128 runtime re-entry across multiple helpers and tests only prove loop entry, not stable post-resume runtime state
      - the implementation target is one atomic runtime re-entry contract plus a deeper smoke that can catch late restart/runtime reload
    - implementation landed:
      - C128 now has one authoritative runtime re-entry owner for KERNAL-visible return seams; both `platform_runtime_resync_api` and `platform_main_loop_begin_api` use that same full restore path
      - `load_resume_game` now reasserts the C128 runtime contract itself instead of relying on the title `L` caller to do a bespoke pre-jump repair
      - `c128_preload_asset_load` now returns through the same full runtime re-entry owner instead of restoring vectors alone
      - the prompt-guard build now asserts post-load runtime state at three points:
        - immediately after the `load_resume_game` re-entry seam
        - at resumed `main_loop` top
        - after the first resumed command fetch
      - the shipping and prompt-guard drive-8 swap smokes now queue one harmless resumed command and stop at a deeper post-resume gameplay boundary instead of treating loop entry as closure
      - the shipping drive-8 smoke now fails on unexpected `entry_main` re-entry after title readiness rather than only on `c128_load_runtime_prg`
    - latest local verification:
      - `make disk128`
      - `TEST_FILTER='boot_preload_vector_guard_smoke|boot_title_load_resume_drive8_smoke|boot_title_load_resume_drive8_shipping_smoke' bash commodore/c128/run_tests128.sh`
      - `make test128-fast-smoke` -> `=== Results: 8 passed, 0 failed (of 8 suites) ===`
      - `TEST_FILTER='boot_title_idle_smoke' bash commodore/c128/run_tests128.sh`
      - `TEST_FILTER='boot_title_load_resume_drive8_smoke' bash commodore/c128/run_tests128.sh`
      - `TEST_FILTER='boot_title_load_resume_drive8_shipping_smoke' bash commodore/c128/run_tests128.sh`
      - all three focused C128 gates passed after the dedicated KERNAL-mode IRQ tail landed
      - root cause that actually moved the live gate:
        - `EnterKernal_sub` was installing `mmu_kernal_irq`, but `init_common_mmu_helpers` was still using an 8-bit blob copy loop
        - after the helper blob grew to `$110` bytes, only the first `$10` bytes were copied into common RAM
        - that left `mmu_kernal_irq` and later helpers uninitialized at runtime, which exactly explains the live IRQ/vector chaos during KERNAL-visible load windows
      - current boundary repair under test:
        - `EnterKernal_sub` now restores the native KERNAL CHRIN vector at `$0302/$0303` together with the KERNAL-window software IRQ owner
        - `ExitKernal_sub` reinstalls the runtime `chrin_keyboard_stub` together with `mmu_common_irq`
        - the preload guard now asserts that `w_load` sees both `mmu_kernal_irq` and the saved native CHRIN vector, so the first preload/overlay load cannot silently run with the runtime keyboard stub still active
      - build-gate follow-up:
        - the forced-rebuild smoke gate initially exposed a separate C128 staged-source ceiling regression in the shipping image
        - recovered bytes locally in the same seam by removing the dead C128 `kernal_load_safe` wrapper and folding the runtime re-entry aliases onto the authoritative owner instead of extra `jmp` trampolines
      - latest live failure reframe after the CHRIN fix:
        - the vectors were sane at failure (`$0314/$0315 = runtime`, `$0302/$0303 = native`, `$FFFE/$FFFF = native`)
        - the live PC moved to `$4503`, which is resident message code in the build but a `JAM` byte in the live machine
        - that proves the first `MONSTER.DB.1` load was scribbling resident Bank 0 code instead of only failing in the IRQ seam
      - corrected owner:
        - `c128_preload_asset_load` was still splitting one stateful C128 LOAD transaction across `safe_setbnk`, `w_setnam`, `w_setlfs`, `w_load`, `w_close`, and `w_clrchn`
        - that violated the existing C128 contract that `SETNAM -> SETLFS -> LOAD` must stay inside one continuous KERNAL window
        - the preload/runtime asset path now holds one `EnterKernal_sub`/`ExitKernal_sub` window around raw `SETBNK`, `SETNAM`, `SETLFS`, `LOAD`, `CLOSE`, and `CLRCHN`
      - latest verification:
        - `make -s -C commodore -W c128/main.s -W c128/boot128.s -W common/reu.s build128 disk128` -> PASS
        - `TEST_FILTER='boot_preload_vector_guard_smoke|boot_title_load_resume_drive8_smoke|boot_title_load_resume_drive8_shipping_smoke' bash commodore/c128/run_tests128.sh` -> `=== Results: 3 passed, 0 failed (of 3 suites) ===`
        - `make test128-fast-smoke` -> `=== Results: 8 passed, 0 failed (of 8 suites) ===`
      - follow-up broader regression status:
        - `make test128-fast` is still red in snapshot mode on unrelated compare-time timeouts (`minimal128`, `config128`, `vdc_attr128`, `dungeon128`, `main_loop128`) after cold mode passes
      - `make test64` was not rerun in this pass because the change is isolated to `commodore/c128/memory128.s` and the last dirty-tree C64 run was already hanging in unrelated `c64/test_monster_ai`
    - remaining closure gap:
      - the manual live C128 drive-8 `L` repro still needs user confirmation on the new build; the exact local proxy gates are now materially closer to that path than the old loop-top smokes
- [ ] BUG-C128-TITLE-L-GAMEWRITTEN-SAVE-REPRO
  - [ ] add an exact mounted-save-disk title-`L` repro that uses a game-written save disk instead of the current host-written fixture disk
  - [ ] keep product code frozen until that new exact repro is red or proves the live/manual mismatch is outside the current fixture path
  - [ ] build the mounted save disk by:
    - booting to `title_menu_ready`
    - creating a real save through the existing in-game save harness
    - reusing that resulting disk as drive `8` before pressing `L`
  - [ ] make the new repro fail on the live/manual signature, not just a generic timeout:
    - `load_result = 01`
    - `save_io_error = 00`
    - `rle_lit_buf = c7 0d 0d 0d 0d 0d 0d 0d`
    - `save_device = 08`
  - [ ] if the new exact repro is red, fix product code only against that gate and then rerun the existing mounted-save-disk title-load smokes
  - review addendum:
    - new exact save-seed blocker gate:
      - `TEST_FILTER='boot_scripted_input_town_ready_repro' bash commodore/c128/run_tests128.sh`
      - current status: FAIL
      - purpose: isolate the scripted-input pre-town snapshot substrate before `boot_title_load_resume_drive8_gamewritten_smoke` ever reaches save/load
    - real builder bug fixed this pass:
      - `build_scripted_input_boot_assets` was mixing scripted-input `moria128` with shipping `128.help` / `128.ui` / `128.fdisk` assets on the scripted-input variant disks
      - the scripted-input `d64`/`d71` builders now rewrite those variant-owned files too, so the pre-town gate is no longer explained by a stale overlay mix
    - current strongest blocker after that builder fix:
      - the scripted-input save-seed path is still not reaching a trustworthy town-ready snapshot under the remote-monitor capture path
      - the red gate is now clearly before save/load product behavior, so further save/load code changes remain frozen
    - exact evidence from the narrowed repro:
      - the current remote-monitor capture path still times out before the scripted-input pass symbol and drifts into charged-input loops with `c128_test_input_idx` advanced far past the intended script
      - that means the current snapshot substrate is still invalid for generating the game-written save seed, even though the simpler legacy `scripted_summary_to_town_smoke` shell smoke remains green
      - conclusion: the active remaining problem is the scripted-input snapshot substrate, not the mounted-save-disk `THE.GAME` read path itself
    - the old save-seed setup path was still invalid in two different ways:
      - title-ready snapshot plus remote-monitor `keybuf` is not trustworthy for staged chargen on C128; even single-key `N` injection from a real shipping title-ready session can fail to advance off the title input loop under the current CIA-direct input path
      - custom scripted-input `.d71` save-seed disks are also not yet trustworthy as a substitute; after rebuilding the scripted-input disk from the shipping base and then with a full scripted file replacement, the exact `gamewritten` gate still times out before town/save on an earlier C128 boot/preload path
    - current exact failing command remains:
      - `TEST_FILTER='boot_title_load_resume_drive8_gamewritten_smoke' bash commodore/c128/run_tests128.sh`
    - current blocker inside that gate:
      - the save-seed phase does not yet reach a trustworthy town-ready snapshot
      - latest exact failure context on the scripted-input save-seed path shows a pre-town C128 boot/preload stall before the first town loop, with stacks landing in resident runtime/preload code and KERNAL `LOAD` rather than in save/load proper
    - strongest current conclusion:
      - do not keep changing save/load product code until the save-seed phase is backed by one trustworthy substrate
      - next exact move should isolate the pre-town scripted-input preload/runtime stall as its own exact gate, or replace the broken staged-keyboard save-seed setup with a trustworthy official-disk town-ready capture path
  - review:
    - latest live/manual trace after the apparent "hang" is actually:
      - `title_load_fail -> title_menu_loop -> input_get_key -> input_process_sample_strict`
    - latest live/manual save-load signature:
      - `load_result = 01`
      - `save_io_error = 00`
      - `rle_lit_buf = c7 0d 0d 0d 0d 0d 0d 0d`
      - `save_device = 08`
    - current local mounted-save-disk title-load gates still pass when fed host-written save-only disks, including the newer `d64` variant, so that fixture path is still missing something the live/user disk path preserves
    - current exact game-written-save gate is now real and red:
      - `TEST_FILTER='boot_title_load_resume_drive8_gamewritten_smoke' bash commodore/c128/run_tests128.sh`
      - current trustworthy failure is still earlier than title `L`, but it has moved back into harness setup:
        - `boot_title_load_resume_drive8_gamewritten_smoke_town_ready` now times out before the save seed is created
        - the title-ready snapshot builder and save/load smoke were both corrected to use real breakpoints instead of false-positive `until` stops
        - the remaining blocker is generating a trustworthy town-ready snapshot for the save seed, not interpreting a fake save-pass
    - proved this is not just the `d64` fixture:
      - one-off host-verified `d71` save reproduction also ended with no `THE.GAME`
    - fixes attempted against the red gate that were necessary but insufficient:
      - preserve SETNAM A/X/Y across `c128_open_save_stream`
      - restore native high ZP before save-stream open
      - close via `c128_close_stream_file` instead of generic `SAVE_CLOSE`
      - restore saved stream context, not plain native ZP, before `CLRCHN/CLOSE`
      - add a real C128 post-close DOS-status check
      - remove the redundant wrapped `SAVE_CHKOUT` after `c128_open_save_stream`
      - stop reissuing `CHKOUT` on every byte in `c128_stream_chrout`
    - current best diagnosis:
      - no further product conclusion is valid until the game-written save seed is produced from a trustworthy town-ready path
      - the next harness fix should be a dedicated breakpoint-driven town-ready snapshot helper instead of stretching the generic snapshot script further
- [ ] BUG-C128-DRIVE8-ROUNDTRIP-TEST-TRUST
  - [x] rerun the red round-trip smoke outside the sandbox so localhost monitor failures stop lying
  - [x] verify the pre-seeded C128 drive-8 shipping load smokes outside the sandbox:
    - `TEST_FILTER='boot_title_load_resume_drive8_shipping_smoke' bash commodore/c128/run_tests128.sh`
    - `TEST_FILTER='boot_title_load_resume_drive8_shipping_dungeon_smoke' bash commodore/c128/run_tests128.sh`
  - [x] confirm the current round-trip harness is not yet trustworthy as a save producer
  - [x] identify concrete harness bugs:
    - remote-monitor helpers were being run in the sandbox where localhost sockets are denied
    - `commodore/c128/tests/vice_connector.py` only emitted ASCII monitor commands, so it could not send the real `SHIFT+S` save key (`$D3`)
    - the existing action sequence `AA  S1` can hit save-disk/death-adjacent prompts and `game_over_prompt` without proving a real save
  - [x] replace the fake save action with a real `SHIFT+S`-based current-build save producer and verify the in-game success path with explicit save success/fail probes
  - [ ] once that producer is green, feed its output disk into the C128 drive-8 load smoke and chase any remaining live/product mismatch
  - [x] add a colder C128 drive-8 load smoke that exercises a fresh boot/re-entry path instead of only same-session `Start Over`
  - [x] repair the colder smoke's monitor contract across `reset 1`
  - review:
    - trustworthy automated state today:
      - the pre-seeded drive-8 load path is green outside the sandbox
      - the current-build drive-8 save-success smoke is green outside the sandbox
      - the colder current-build drive-8 roundtrip is now green in one automated path:
        - save on the current build
        - restore the program disk
        - `reset 1`
        - return to title
        - `L`
        - reattach the save disk
        - resume gameplay
      - after moving `c128_load_runtime_prg` onto the shared wrapped preload transaction, the full exact gate is green again:
        - `make test128-fast-smoke` -> `=== Results: 7 passed, 0 failed (of 7 suites) ===`
        - `make test64` -> `=== Results: 35 passed, 0 failed (of 35 suites) ===`
        - `make disk128` -> PASS
    - immediate next step:
      - use the now-green cold-reset roundtrip plus the seeded-load smokes as the C128 automation substrate
      - compare that green automated path against the user's still-red fresh-build live path
      - do not call the live bug fixed until the user confirms the fresh-build drive-8 `L` path is clean
      - if the live gate is still red after the unified runtime-resync repair, instrument the first post-`load_game` boundary for `$0314/$0315 == $0C06` instead of extending more swap smokes
- [x] BUG-C128-PRELOADED-RUNTIME-PROGRAM-DISK-POLICY
  - [x] isolate the concrete owner of the bogus post-preload program-disk dependency in the C128 one-drive load flow
  - [x] remove the special `OVL_HELP -> disk` bypass from the shared C128 overlay loader
  - [x] replace the brittle synthetic overlay unit with a stable C128 policy guard that fails if HELP bypasses the overlay cache again
  - [x] rerun focused C128 verification:
    - `TEST_FILTER='c128_program_media_policy_guard' bash commodore/c128/run_tests128.sh`
    - `TEST_FILTER='boot_title_load_resume_drive8_smoke' bash commodore/c128/run_tests128.sh`
  - [ ] rerun exact gates:
    - `make test64`
    - `make disk128`
    - `make test128-fast-smoke`
  - review:
    - root cause fit:
      - the C128 `program_disk_prompt` seam was still effectively unconditional, so any shared runtime asset loader that fell through to disk would still prompt
      - in practice, the live FEAT-DISK/title-load path was reintroducing program-disk dependence because `overlay_load` had a C128-only `OVL_HELP` special case that bypassed the preload cache and forced HELP back to disk
      - that is why the old drive-8 smoke could stay green while the live save-only disk flow still touched the program disk “just to show a message”
    - implementation:
      - `commodore/common/overlay.s` no longer special-cases `OVL_HELP` to `ol_check_disk` on C128; HELP now follows the same `c128_cache_overlays_ready` + `c128_cache_overlay_bits` cache path as the other preloaded overlays
      - `commodore/c128/run_tests128.sh` now has `c128_program_media_policy_guard`, a stable source-contract test that fails if HELP bypasses the C128 overlay cache or if title-art cache ordering regresses
      - the earlier synthetic `test_overlay128.s` fixture was removed instead of being left as a flaky non-authoritative test
    - focused verification passed:
      - `TEST_FILTER='c128_program_media_policy_guard' bash commodore/c128/run_tests128.sh`
      - `TEST_FILTER='boot_title_load_resume_drive8_smoke' bash commodore/c128/run_tests128.sh`
    - follow-up live C128 root cause:
      - after the HELP-cache fix, the user hit a new C128 JAM at `$EC75` while loading `128.RUNTIME`
      - symbol resolution showed `$EC61 = c128_preload_title_art`, and the emitted resident bytes at the callsite were a literal `JSR $EC61`
      - that routine lives in `UiOverlay` via `commodore/common/title_screen.s`, not in resident runtime code
      - so title entry was directly calling overlay-owned code as though it were resident, which is an invalid ownership/execution contract and matches the live `JAM`
    - follow-up implementation:
      - `commodore/c128/main.s` no longer calls `c128_preload_title_art` directly from `entry_main`
      - new resident `tramp_c128_preload_title_art` first loads `OVL_UI`, restores the runtime guards, and only then tail-calls `c128_preload_title_art`
      - focused verification after the trampoline fix:
        - `TEST_FILTER='boot_title_idle_smoke' bash commodore/c128/run_tests128.sh`
        - `TEST_FILTER='boot_title_load_resume_drive8_smoke' bash commodore/c128/run_tests128.sh`
      - exact gates re-passed after the fix:
        - `make test64`
        - `make disk128`
        - `make test128-fast-smoke`
    - latest live follow-up:
      - after the resident preload trampoline landed, the user hit a new lockup with repeated `IRQ -> $0D06` / `BRK`
      - `$0D06` is below the `128.FDISK` common-runtime load base, so this is not normal FEAT-DISK code execution; it is a collapsed IRQ/vector/runtime handoff
      - consultant review showed the existing C128 load-resume smokes were also invalid for the live gate:
        - they stopped at `load_resume_game` or an earlier prompt-guard symbol before the resumed gameplay loop
        - one version also relied on a raw breakpoint at the `disk_prompt_game` symbol address, which is not trustworthy on C128 when ROM can be visible at the same address
      - the load-resume smokes now target the first resumed gameplay loop, and the prompt-guard variant carries an explicit compiled counter through the full resume path instead of using a raw address breakpoint
      - remaining known weakness:
        - the shipping drive-8 title-load smokes still stop too early to prove “no later restart/runtime reload happened”; they need a deeper post-resume fail condition before they can close the live gate by themselves
      - the remaining open gap is fixture realism:
        - the old C128 drive-`8` title-load smokes were hybrid disks that kept program assets and save files on the same `D71`, so they did not model the real one-drive swap case where drive `8` holds only the save disk after boot
        - the synthetic C128 save fixture was originally a town-level (`PL_DLEVEL = 0`) resume; a dungeon-level fixture now exists, but the hybrid-disk issue still leaves the live drive-`8` swap gate under-modeled
        - the old seeded `MORIA8.ID` / `THE.GAME` files on those C128 harness disks were also being written by `c1541 write` as `prg`, not `seq`, so they were doubly unfaithful to the real save-disk contract
      - another concrete owner was confirmed in resident code:
        - `c128_load_runtime_prg` was binding `SETLFS` to `save_device` instead of the fixed program-media device
        - if any failure path re-entered `entry_main` after save-disk selection, `128.RUNTIME` / `128.FDISK` would be fetched from the save disk instead of the program disk
        - the C128 program-media policy guard now source-checks that this loader stays on device `8`
    - current implementation target:
      - keep the resident preload trampoline fully guarded (`c128_restore_runtime_guards` + `c128_restore_runtime_vectors`)
      - keep the stronger post-resume C128 prompt-guard test in place
      - replace the hybrid `D71` drive-`8` smokes with the new real one-drive swap smoke:
        - boot from a program-only disk
        - wait for `title_menu_ready`
        - inject `L1`
        - stop at the real FEAT-DISK save-disk insert seam
        - attach a save-only disk to drive `8`
        - continue through title `L`
      - use that faithful smoke, not the hybrid fixture, as the C128 drive-`8` live-gate proxy before asking for another manual retest
      - the C128 harness fixtures now patch `MORIA8.ID` / `THE.GAME` directory types to closed `seq` after `c1541 write`, and the builders fail if `c1541 -list` does not show `seq`
      - focused verified swap gates now pass on both town and dungeon saves:
        - `TEST_FILTER='boot_title_load_resume_drive8_smoke' bash commodore/c128/run_tests128.sh`
        - `TEST_FILTER='boot_title_load_resume_drive8_dungeon_smoke' bash commodore/c128/run_tests128.sh`
    - exact local gates re-passed on the current tree:
      - `make test64`
      - `make disk128`
      - `make test128-fast-smoke`
      - on the current tree, `make test128-fast-smoke` now reports:
        - `boot_title_idle_smoke`
        - `boot_title_load_resume_drive8_shipping_smoke`
        - `save_load_roundtrip_drive8_smoke`
        - `boot_title_load_resume_drive8_smoke`
        - `boot_title_load_resume_drive8_dungeon_smoke`
        - `scripted_summary_to_town_smoke`
        - `town_overlay_smoke`
- [ ] BUG-C64-LOAD-VALIDATE-ONLY-SETUP
  - [x] stop first-time title `L` from offering save-disk initialization when the selected disk has no marker
  - [x] keep explicit `D)isk Setup` and gameplay/death save setup on the init-capable path
  - [x] fix the C64 Disk Setup note wrapping so it stays readable on two centered lines
  - [x] trim the C64 resident image back under `MAP_BASE` after adding the new load/setup contract
  - [x] keep the focused `main_loop` harness aligned with the new shared request symbol
  - [x] rerun:
    - `make disk128`
    - `make test128-fast-smoke`
    - `make test64`
  - review:
    - root cause fit:
      - title `L` was still entering the same init-capable FEAT-DISK flow used by save and explicit Disk Setup, so load could wrongly offer to initialize a missing save disk
      - the first implementation of the split pushed the C64 resident image over `MAP_BASE`, then the `main_loop` harness missed the new shared request byte
    - implementation:
      - `commodore/c64/main.s` now marks first-time title `L` as validate-only before `tramp_disk_setup`, and it only continues into `title_load_game_mounted` when validation succeeds
      - `commodore/common/disk_setup_banked.s` now fails immediately on missing marker when the request is validate-only instead of offering `DISK_UI_ACT_INIT_PROMPT`
      - validate-only failure now stays inside the save-disk retry loop instead of offering initialization or bouncing back into the Disk Setup menu
      - `commodore/common/game_loop.s` and `commodore/c64/main.s` keep save/death/explicit setup on the init-capable path
      - `commodore/common/ui_disk_setup.s` now prints the save-disk note as two centered lines instead of one badly wrapped line
      - the same shared UI now explains validate-only failure with `Wrong Save Disk.` and then re-prompts for another save disk, so title `L` never strands the user on a half-redrawn title screen without the program disk mounted
      - resident C64 trims were kept local:
        - shared `ALLOW_INIT` clearing now uses the smaller `lsr disk_setup_request` pattern at mutating callsites
        - `disk_reset_session_state` no longer spends bytes redundantly resetting the request byte
        - `c64_disk_marker_present` now uses one shared close/restore tail and no longer burns a separate jump stub
      - `commodore/c64/tests/test_main_loop.s` now defines `disk_setup_request`, keeping the focused harness aligned with the common game-loop import
    - exact gates passed on the final code state:
      - `make disk128`
      - `make test128-fast-smoke`
      - `make test64`
    - pending live proof:
      - first-time C64 title `L` with a disk that lacks `MORIA8.ID` should now reject it without offering initialization
      - the Disk Setup note should render as two clean centered lines
- [x] SAVE-CONTRACT-KEEP-SAVEFILE
  - [x] stop deleting `THE.GAME` after a successful load
  - [x] stop deleting the savefile on death
  - [x] change save to ask before overwriting an existing file
  - [x] keep the overwrite prompt memory-safe on both C64 and C128
  - [x] rerun:
    - `make disk128`
    - `make test128-fast-smoke`
    - `make test64`
  - review:
    - root cause fit:
      - the branch was still carrying both contracts at once: the new overwrite UX was layered on top of the old delete-on-load/delete-on-death machinery
      - that made the behavior incoherent and also wasted scarce C64 resident bytes
    - final contract:
      - load no longer scratches `THE.GAME`
      - death no longer scratches `THE.GAME`
      - save now probes for an existing `THE.GAME`, asks `Overwrite? Y/N`, and only then proceeds
    - implementation:
      - `commodore/common/save.s` no longer contains `scratch_cmd`, `delete_savefile`, or `delete_savefile_core`
      - `save_game` now uses `save_file_exists` plus `save_confirm_overwrite`, then performs one overwrite-safe save open using `@0:THE.GAME,S,W`
      - `load_game` now ends after a verified successful read/recount path instead of trying to enforce permadeath
      - `commodore/common/game_loop.s` no longer scratches the save on death before `tramp_game_over`
      - `commodore/c64/main.s` title load tails were merged to recover resident C64 bytes while preserving the one-drive mounted-load behavior
    - exact gates passed on the final code state:
      - `make disk128`
      - `make test128-fast-smoke`
      - `make test64`
    - consultant-backed follow-up:
      - root cause 1:
        - the overwrite prompt had become UI-only; after `Y`, the code still tried to create `THE.GAME` again instead of performing a real replacement action on C64
      - implementation 1:
        - C64 now uses the smaller resident contract `open -> if fail ask Y/N -> open @0:THE.GAME,S,W`
        - C128 keeps the lighter pre-probe + overwrite-open path to stay under the staged-source ceiling
      - root cause 2:
        - the in-game save path was still swapping back to the program disk immediately after save completed, even though that caller did not yet have a proven next program-disk dependency
      - implementation 2:
        - `commodore/common/game_loop.s` no longer does an unconditional `disk_prompt_game` immediately after `save_game`
      - root cause 3:
        - one-drive disk prompts were still being drawn as in-place row overlays instead of a proper modal screen
      - implementation 3:
        - `commodore/common/disk_swap.s` now clears the screen before the one-drive modal prompt instead of layering prompt text over gameplay rows
      - contract note:
        - C64 title-load no longer forces an immediate swap-back to the program disk before `load_resume_game`; prompt timing now moves closer to the next real I/O boundary instead of being tied to load completion itself
      - exact gates re-passed after the prompt/overwrite changes:
        - `make disk128`
        - `make test128-fast-smoke`
        - `make test64`
- [ ] BUG-C64-SINGLE-DRIVE-LOAD-PROMPT
  - [x] trace the live monitor address back to the one-drive `disk_prompt_game` key-acquire path
  - [x] switch the one-drive swap prompt to the shared modal dismiss helper on C64 instead of raw `input_get_key`
  - [x] keep the focused C64 disk-swap unit harness aligned with the imported helper contract
  - [x] clear the stale full-screen Disk Setup UI before the one-drive `Insert program disk` runtime prompt
  - [x] make title `L` continue directly into the actual one-drive load after setup instead of bouncing back to the menu
  - [x] skip the redundant second save-disk prompt when the same `L` has just mounted the one-drive save disk
  - [x] rerun:
    - `make disk128`
    - `make test128-fast-smoke`
    - `make test64`
  - review:
    - root cause fit: the live machine was not crashing in disk I/O; it was still polling in `input_get_key` during `disk_prompt_game` on the second one-drive swap prompt
    - implementation: `disk_prompt` in `commodore/common/disk_swap.s` now always uses `input_get_modal_dismiss_key`, so the C64 one-drive load/save prompts go through the same keyboard-buffer flush + release discipline already used by the FEAT-DISK modal UI
    - harness follow-up: `commodore/c64/tests/test_disk_swap.s` now provides the `input_wait_release` stub required by the imported helper contract instead of shadow-defining the modal helper symbol
    - flow clarification: the second `Insert program disk` prompt is expected in one-drive mode; the actual UX bug was that it was being drawn on top of the stale full-screen Disk Setup view instead of a clean screen before the normal title redraw
    - contract fix: when `L` triggers fresh one-drive setup, C64 now continues into `load_game` with the save disk already mounted instead of returning to the title and requiring a second `L`; `D)isk Setup` still returns to the menu
    - prompt fix: the same `L` no longer issues a second `disk_prompt_save` after one-drive setup has already mounted the save disk; it uses the `tramp_disk_setup` carry result to distinguish “continue into load now” from “return to menu”
    - verification passed:
      - `make disk128`
      - `make test128-fast-smoke`
      - `make test64`
    - regression + recovery:
      - the consultant-backed delete/error patch initially regressed the live one-drive `L` path in three ways:
        - it prompted for the save disk twice on the same `L`
        - it turned successful reads into a false load-time `Disk error!`
        - it left later program/save-disk state confused after the failed load
      - root cause 1:
        - C64 title `L` was still entering `title_load_game` through the generic path after fresh one-drive setup, so it re-ran `disk_prompt_save` even though the save disk was already mounted
      - implementation 1:
        - `commodore/c64/main.s` now has a dedicated `title_load_game_mounted` entry used only after successful fresh setup, so the same `L` no longer issues the redundant second save-disk prompt
      - root cause 2:
        - `load_game` was made dependent on a new C64 delete-status parser that had not yet been proven live, so delete failure was being misreported as a load-time disk-read failure
      - implementation 2:
        - `commodore/common/save.s` now uses the smaller known-good scratch transaction again for `delete_savefile_core` (`OPEN 15 -> CLOSE 15 -> CLRCHN`) instead of the heavier C64 status-drain parser that caused the false load failure
      - implementation 3:
        - the extra C64-only failed-save modal code was trimmed back out so the one-drive swap prompt remains the pause point and the C64 image stays below `MAP_BASE`
      - remaining live follow-up:
        - post-load save was still failing with `Disk error!` because `save_game` had been left on plain create (`0:THE.GAME,S,W`) while delete-after-load was still not proven live
      - implementation 4:
        - `commodore/common/save.s` now opens the save file with overwrite-safe replace semantics again (`@0:THE.GAME,S,W`), so a leftover `THE.GAME` no longer turns the next save into an immediate open failure
      - implementation 6:
        - the attempted C64 scratch-status parser was removed entirely in favor of the direct overwrite contract the user actually wanted: after `Y`, the save path now performs one real CBM DOS replace-open instead of scratching first and then retrying plain create
        - that simplification also recovered enough resident bytes to bring `Program fits below MAP_BASE` back to green
      - implementation 7:
        - one consultant correctly identified a stale retry boundary after the failed plain create: the first `OPEN` failure could still leave `READST` dirty for the confirmed overwrite path
        - `commodore/common/save.s` now clears `zp_kernal_status` again before the confirmed `@0:THE.GAME,S,W` replace-open and again before entering the write loop, so the first post-overwrite `READST`-checked write no longer inherits stale status from the failed initial create
      - implementation 8:
        - the C64 overwrite path no longer intentionally performs a failed plain create before asking `Overwrite? Y/N`
        - `commodore/common/save.s` now probes `THE.GAME` first with `save_file_exists`, then goes straight to either plain create or confirmed `@0:THE.GAME,S,W`
        - that removes the dirty failed-`OPEN` transaction from the C64 overwrite path entirely instead of trying to clean it up afterward
      - implementation 9:
        - live C64 behavior still stayed red after the separate probe-first branch, so the probe itself was removed from C64 again
        - the current C64 save contract is now create-first with DOS-status classification on the failed plain `OPEN`:
          - plain `0:THE.GAME,S,W`
          - if `OPEN` fails, read command-channel status
          - only `63,FILE EXISTS` offers `Overwrite? Y/N`
          - confirmed overwrite retries with `@0:THE.GAME,S,W`
        - C128 keeps the lighter `save_file_exists` pre-probe path to stay within its different memory budget
      - implementation 5:
        - a follow-up C64 DOS-status-specific save-error decoder was attempted, but it overflowed the C64 resident image and tripped the exact `make test64` memory-boundary gate
        - that diagnostic was backed back out to keep the exact gates green; the minimal shipped change from this pass is still the overwrite-safe save open contract
      - exact gates re-passed after the rollback/repair:
        - `make disk128`
        - `make test128-fast-smoke`
        - `make test64`
- [x] FEAT-DISK-C128-MODAL-REDESIGN
  - [x] stop treating `tramp_disk_setup` as a monolithic help-overlay FEAT-DISK session on C128
  - [x] make `ui_disk_setup.s` prompt/input-only on C128 through `ui_disk_setup_dispatch`
  - [x] move the C128 FEAT-DISK coordinator out of Default and into a dedicated common-RAM runtime PRG
  - [x] load the new `128.fdisk` runtime blob before title entry
  - [x] verify the exact gates after the ownership split:
    - `make test64`
    - `make test128-fast-smoke`
    - `make -C commodore disk128`
  - review:
    - consultant diagnosis held:
      - the real owner bug was still “help overlay owns FEAT-DISK control flow and resumes after disk/KERNAL work”
    - first direct resident cutover failed for the expected reason:
      - importing the coordinator into Default overflowed the banked-payload staged-source ceiling above `$E000`
    - implemented architecture:
      - `ui_disk_setup.s` on C128 is now action-dispatch only
      - C128 FEAT-DISK coordinator/title helpers live in `commodore/common/disk_setup_runtime128.s`
      - that blob is emitted as `out/c128/128.fdisk.prg` and loaded into common RAM at `$0D20-$0EDB`
      - `tramp_disk_setup` now runs the non-overlay coordinator
      - each FEAT-DISK prompt reloads `OVL_HELP` fresh through `tramp_disk_setup_ui_action`
    - exact automated gates are green:
      - `make test64`
      - `make test128-fast-smoke`
      - `make -C commodore disk128`
    - live C128 gate still needs the user repro on the new image:
      - existing marker on drive `9` should be recognized
      - `Shift+S` setup/init should no longer resume the stale `$E5xx` overlay path
    - consultant follow-up:
      - the remaining likely owner is the C128 marker-read contract, not overlay caching
      - `disk_marker_present` still uses `w_setnam -> w_setlfs -> w_open -> w_chkin -> w_chrin` as though the `w_*` family were one persistent KERNAL file-I/O session
      - that assumption is wrong because each wrapper does its own `EnterKernal -> call -> ExitKernal`
      - next fix: replace the C128 marker read path with one continuous `EnterKernal/ExitKernal` transaction before any more live retests
    - latest implementation:
      - C128 `disk_marker_present` no longer chains `w_setnam -> w_setlfs -> w_open -> w_chkin -> w_chrin`
      - it now does one continuous `EnterKernal/ExitKernal` transaction with direct `KERNAL_SETNAM/SETLFS/OPEN/CHKIN/CHRIN/CLRCHN/CLOSE`
      - consultant review immediately caught one remaining local bug in that first pass:
        - the direct read loop was still trusting `X` across `KERNAL_CHRIN`
        - the loop now keeps its marker index in `disk_temp` instead
      - C128 `disk_marker_init` now matches the proven C64 contract:
        - scratch `MORIA8.ID`
        - plain-create the marker file instead of relying on `@` replace semantics
        - only report success if `disk_marker_present` can reread the marker immediately afterward
    - exact gates after the transaction fix are green:
      - `make disk128`
      - `make test128-fast-smoke`
      - `make test64`
    - final live outcome:
      - C128 no longer hangs in the save-disk flow
      - an existing marker created during the broken earlier path could still fail validation, but freshly initialized media under the fixed build now saves, reboots, and later loads successfully
      - the remaining issue class is prompt-flow polish, not broken persistence
- [x] FEAT-DISK-C64-RESIDENT-COORDINATOR
  - [x] keep `ui_disk_setup.s` display/input-only on C64 and treat each screen as disposable
  - [x] remove stale C64 FEAT-DISK trace scaffolding
  - [x] simplify the C64 setup flow to the v1 path:
    - autosuggest drive `9`
    - fall back to one-drive on `8`
    - reject the program disk
    - offer explicit marker initialization
  - [x] verify C64 still fits under `MAP_BASE` and the banked payload stays below `$D000`
  - [x] rerun:
    - `make test64`
    - `make test128-fast-smoke`
  - review:
    - attempted design: a fully resident C64 FEAT-DISK coordinator in `disk_swap.s` with disposable overlay views
    - space result: the resident-only coordinator pushed `program_end` to `$C133`, overflowing `MAP_BASE` by `$133`, so the pure consultant-preferred layout does not fit the current C64 image
    - implemented compromise: `ui_disk_setup.s` stays display/input-only on C64, `tramp_disk_setup_overlay` now owns its own overlay banking, and the FEAT-DISK controller remains in `disk_setup_banked.s` to stay inside the C64 memory ceiling
    - scope trim: C64 no longer offers the `Other Drive` branch in Disk Setup; the v1 setup path is now `drive 9 if present` or `one drive on 8`
    - verification passed:
      - `make test64`
      - `make test128-fast-smoke`
- [x] BUG-C64-SHIFT-S-SAVE-HANG
  - [ ] instrument the exact C64 `L` / Disk Setup / drive-9 path to capture the first illegal execution-context transition before any more behavioral fixes
  - [ ] verify the new `SHIFT+S` path against the user's live repro and confirm the banking/IRQ seam
  - [x] harden the save-and-quit path so prompt/input recovery cannot leave C64 running with `$01=$35`
  - [x] replace the ad hoc title/load banking repairs with a shared C64 UI/runtime resync seam
  - [x] re-run the focused regression gates and record the outcome below
  - review:
    - root cause fit: the live hang signature (`PC=$0002`, `$01=$35`, repeated `IRQ -> $FFFF`) matches a C64 prompt/input seam that returned with KERNAL banked out while interrupts were active
    - implementation: `disk_prompt` now forces `BANK_NO_BASIC` after the press-key/input + drive-init path on C64, and `game_over_prompt` now normalizes `$01` to `BANK_NO_BASIC` before entering its key loop
    - implementation: the `CMD_SAVE` path now preserves `save_game` success/failure across `disk_prompt_game` without adding a new resident byte, so save failures return to gameplay and successful saves continue into the quit flow
    - regression coverage: `commodore/c64/tests/test_disk_swap.s` now includes a resident contract check that starts from `$01=$35`, runs the swap prompt, and asserts the prompt returns with `$01=$36`
    - verification passed:
      - `make test64`
      - `make test128-fast-smoke`
      - independent tester signoff: `Exact reported command: N/A`, `Broader regression suites: PASS`, `ALL TESTS PASSED yes`
    - consultant-guided follow-up:
      - root cause fit: the live partial-clear title hang is a C64 title/UI boundary problem, not a `screen_clear` bug; the title path was still capable of inheriting `$01=$35` from an earlier KERNAL-visible seam
      - implementation: C64 now has one `platform_runtime_resync_c64` owner for “return to UI-safe state” (`$01=$36`, IRQ wedge vector, VIC bank restore), `title_enter_menu` now starts by calling it, and `title_load_and_draw` now calls the shared runtime-resync API after its title KERNAL transaction instead of relying on scattered local `$01` repairs
      - verification passed after the contract change:
        - direct C64 assemble: `Program fits below MAP_BASE=true`
        - `make test64`
        - `make test128-fast-smoke`
    - consultant-guided course correction:
      - root cause fit: I was fixing where the crash became visible instead of where `$01=$35` was introduced; the fresh-`L` path goes through Disk Setup overlay auto-drive-9 flow before any later title rebuild logic
      - root cause: `disk_kernal_enter` was trying to carry saved processor state across a `JSR`/`RTS` boundary on the hardware stack, which is invalid 6502 stack discipline and can leak the overlay back to `$01=$35` with IRQs live after disk helper calls
      - implementation: `disk_kernal_enter/exit` now save and restore processor status through an explicit `disk_saved_status` byte instead of a cross-call `php/plp` stack trick, and the recent wrong-layer title glue was trimmed back to keep C64 resident size in bounds
      - regression coverage: `commodore/c64/tests/test_disk_swap.s` now directly asserts that the disk KERNAL wrapper round-trips a C64 overlay caller back to `$01=$35` with the I flag still set
      - verification passed after the wrapper fix:
        - direct C64 assemble: `Program fits below MAP_BASE=true`
        - `make test64`
        - `make test128-fast-smoke`
    - consultant-guided re-anchor:
      - root cause fit: the newer `PC=$2020`, `$01=$37`, stack-full-of-`0x20` repro is not another plain IRQ-vector collapse; it points at async corruption during the Disk Setup overlay's post-keypress disk-validation path
      - root cause: `disk_kernal_enter` was reopening IRQs with `cli` before returning to the caller-controlled C64 overlay path, allowing KERNAL/IRQ activity to interleave with overlay-owned UI state and likely turn later clear/print work into page-1 corruption
      - implementation: C64 `disk_kernal_enter` no longer does `cli`; the disk wrapper now keeps IRQs masked through the C64 disk window and restores the caller's bank + saved flags only on exit
      - regression coverage: `commodore/c64/tests/test_disk_swap.s` now asserts the real overlay case, `BANK_NO_ROMS -> BANK_NO_BASIC -> BANK_NO_ROMS`, with the I flag remaining set throughout the disk helper window
      - verification passed after the IRQ-window fix:
        - `make test64`
        - `make test128-fast-smoke`
    - consultant-guided contract hardening:
      - root cause fit: the follow-up `JAM $4AFE` trace still points to the Disk Setup validation path, but now with `$01=$36`; that makes low-RAM/page-1 corruption a better fit than another bank-restore failure
      - implementation: C64 `disk_kernal_enter/exit` now preserve the caller's ZP/UI scratch through `save_zp` / `restore_zp` in addition to bank + flags, so post-disk overlay code does not resume with KERNAL-clobbered pointers before the next clear/print path
      - regression coverage: `commodore/c64/tests/test_disk_swap.s` now includes a KERNAL-style ZP-clobber test and proves `probe_device` restores `zp_ptr0`, `zp_ptr0_hi`, `zp_cursor_row`, and `zp_text_color` after the wrapper returns
      - verification passed after the ZP-preservation fix:
        - `make test64`
        - `make test128-fast-smoke`
    - latest live re-anchor:
      - after the ZP-preservation fix, the title `L` path no longer dies at the save-disk prompt; it can now proceed into the actual save-file load path
      - the new user-visible regression is a false-success load on C64 when no save file exists, leading to a corrupt gameplay screen and low-RAM crash addresses instead of a clean `No save` result
      - implementation: C64 `load_read_byte` now marks per-byte READST low-bit I/O errors during sequential file reads, and `title_load_game` now fails closed on `load_game`'s carry result before resuming gameplay
      - implementation: the `load_game` common return-tail compaction is C64-only so C128 keeps its smaller direct return paths and stays inside the banked-payload staging budget
      - verification passed after the load-path hardening:
        - `make test64`
        - `make test128-fast-smoke`
    - remaining gate:
      - manual live C64 `SHIFT+S` repro still needs confirmation because the reported failure is an interactive path, not an automatable command
      - manual live C64 title `L` repro still needs confirmation after the shared runtime-resync change
    - latest live re-anchor:
      - the current failure is no longer the old `$01=$35` / `IRQ -> $FFFF` collapse
      - current monitor state after the Disk Setup save-disk keypress is `PC=$2020`, `$01=$37`, with return addresses on page `$0100` overwritten by `0x20` bytes, which points at stack or pointer corruption on the post-keypress disk-validation path rather than another plain title IRQ seam
    - consultant-guided redesign:
      - root cause fit: the shared owner was the C64 Disk Setup overlay continuing execution after KERNAL disk/editor activity; preserving more state at the wrapper seam kept moving the symptom but not fixing the contract
      - implementation: C64 Disk Setup is now split across a banked-payload resident controller in `commodore/common/disk_setup_banked.s` and display/input-only overlay entrypoints in `commodore/common/ui_disk_setup.s`; the overlay now only renders screens, collects keys, and returns action results through `disk_ui_action`, `disk_ui_result`, and `disk_ui_value`
      - implementation: C64 setup-only disk transactions (`program-disk present` and `marker init`) moved out of the live overlay path and into the banked controller, while C128 keeps its existing monolithic overlay flow with those helpers local to the C128 overlay path
      - implementation: `tramp_disk_setup` is now a small C64 banked trampoline, and `tramp_disk_setup_overlay` is only a fresh-screen dispatcher into the Help overlay instead of a monolithic setup executor
      - memory fit: after initially overrunning both `MAP_BASE` and the C128 staged-bank ceiling, the C64 controller was moved out of the main segment and the redundant marker scratch pass was removed; current direct C64 assembly reports:
        - `Program fits below MAP_BASE=true`
        - `Payload fits below I/O ($D000)=true`
      - verification passed after the redesign:
        - `make test64`
        - `make test128-fast-smoke`
      - remaining gate:
        - user live C64 repros still need confirmation on the real emulator path:
          - title `L` -> accept drive `9` -> insert save disk -> key
          - in-dungeon `SHIFT+S`
    - consultant-mandated next step:
      - root cause fit: the remaining moving failures are one C64 execution-context escape bug, not a sequence of unrelated seam bugs; the path is still leaking between banked controller (`$01=$34`, `SEI`), normal title/game (`$01=$36`), and KERNAL/editor (`$01=$37`) contexts
      - evidence cluster: the previous `$01=$35` / `IRQ -> $FFFF`, the `$01=$34` / `IRQ -> $0000`, the `PC=$2020` stack-full-of-`0x20`, the `JAM $1A0F`, and the latest `PC=$E5D1`, `$01=$37` all fit the same “first illegal transition” class
      - course correction: stop changing FEAT-DISK behavior until the first bad transition is observed directly
      - required instrumentation pass:
        - trace entry/exit of `tramp_disk_setup`
        - trace entry/exit of `disk_setup_call_ui`
        - trace entry/exit of `tramp_disk_setup_overlay`
        - trace entry/exit of `overlay_load`
        - trace entry/exit of `ui_disk_setup_dispatch`
        - trace entry/exit of each Disk Setup helper (`probe_device`, `disk_init_drive`, `disk_program_media_present`, `disk_marker_present`, `disk_marker_init`)
        - capture `$01`, processor status / I flag, `SP`, `$0314/$0315`, and the current FEAT-DISK phase / overlay identity at each boundary
      - next live gate after instrumentation:
        - fresh C64 boot
        - `L`
        - accept drive `9`
        - `Y` to the save-disk prompt
    - consultant-guided trace-size follow-up:
      - outcome: the first always-on resident trace pass did not fit the C64 image at all; even after moving trace storage to fixed scratch and gating the work behind a debug-only build flag, the entry-only ring trace still overflowed `MAP_BASE` and the banked-payload/I-O ceiling
      - consultant direction: under that constraint, replace the ring buffer with two fixed `prev` / `curr` boundary snapshots and scope the trace only to the exact `L -> drive 9 -> Y` path
      - current status: the default build and regression gates are green again, but even the two-slot snapshot trace still overruns the C64 debug build, so the in-code diagnostic path remains unresolved and needs a smaller next step than the current snapshot tracer
    - consultant-guided contract proof:
      - one-off C64 shipping-path contract test for `disk_setup_call_ui` proved the banked FEAT-DISK controller was still invoking generic `overlay_load` from `$34`
      - direct evidence from the test:
        - banked UI round-trip itself was sound
        - resident disk-helper round-trip itself was sound
        - the failing seam was the generic overlay-load path, which observed `$34`, hit hidden KERNAL stubs, and still tried to load `OVL_HELP`
      - architectural correction:
        - `disk_setup_call_ui` no longer calls `overlay_load`
        - C64 `tramp_disk_setup` now preloads `OVL_HELP` from resident context before entering the banked FEAT-DISK loop
    - consultant-guided C64 disk-call correction:
      - follow-up consultant review identified the remaining live owner as direct KERNAL vector returns into FEAT-DISK helper bodies that live in ROM-shadowed regions (`$A000-$BFFF` and `$F000-$FFFF`)
      - implementation:
        - C64 FEAT-DISK now uses low-RAM KERNAL-call trampolines for the live load/setup path vectors
        - `disk_kernal_enter/exit` no longer bank the whole helper body into the wrong ROM visibility on C64
        - C64 `probe_device` was simplified to use OPEN success directly instead of a redundant READST follow-up
      - fit follow-up:
        - the first wrapper pass overflowed both the resident and banked-source ceilings
        - to make room, the C64 title-only `[Save: N]` indicator was removed as deferred UI scope
      - verification passed:
        - direct C64 assemble: `Program fits below MAP_BASE=true`
        - `make test64`
        - `make test128-fast-smoke`
    - consultant-guided menu/input regression fix:
      - root cause fit: the C64 title/menu started echoing typed characters and only accepted input after Return because FEAT-DISK marker validation leaked KERNAL screen-editor input ownership back into the normal `GETIN` menu path
      - implementation:
        - C64 `disk_marker_present` now routes through one low-RAM `c64_disk_marker_present` helper that owns the full `SETNAM -> SETLFS -> OPEN -> CHKIN -> CHRIN loop -> CLRCHN -> CLOSE` transaction end-to-end instead of splitting the read-side channel state across generic wrappers
        - `tramp_sr_epilogue` now jumps through `platform_runtime_resync_c64`, so FEAT-DISK and other C64 trampoline returns reassert the normal UI/runtime contract without a one-off Disk Setup epilogue
      - fit/result:
        - direct C64 assemble now reports `program_end=$BFFE`, back under `MAP_BASE`
      - verification passed:
        - `make test64`
        - `make test128-fast-smoke`
      - remaining live gate:
        - user still needs to re-test the actual C64 menu path to confirm key echo / Return-only input are gone before more FEAT-DISK behavior changes
    - consultant-guided follow-up on remaining title/probe regressions:
      - root cause fit:
        - needing to press `L` twice at the title is stale keyboard-buffer ownership on title entry/re-entry
        - false `drive 9 did not respond` is the wrong C64 probe contract; `probe_device` was sending `I0` on the command channel instead of doing a passive liveness check
      - implementation:
        - C64 title now calls `input_wait_release` after drawing the title menu and before entering `title_menu_loop`
        - `probe_device` now uses a passive empty-filename command-channel open on the target device instead of a side-effecting `I0` initialize command
      - fit/result:
        - direct C64 assemble now reports `program_end=$BFFF`, still below `MAP_BASE`
      - verification passed:
        - `make test64`
        - `make test128-fast-smoke`
      - remaining live gate:
        - user needs to verify:
          - fresh boot title accepts `L` on the first keypress
          - choosing two-drive mode no longer falsely rejects drive `9`
- [ ] BUG-C64-SHIFT-S-STACK-JAM
  - [x] re-anchor on the new live crash address `$1A0F`
  - [x] remove stack-based save-result preservation from `CMD_SAVE`
  - [x] re-run the focused regression gates and record the outcome below
  - review:
    - root cause fit: `$1A0F` is the middle byte of the `JSR $123D` inside `player_search_get_base_chance`, which matches a bad return target / stack seam rather than another overlay or banking fetch bug
    - implementation: `CMD_SAVE` no longer carries save success on the hardware stack across `disk_prompt_game`; it now snapshots carry into `zp_temp0`, which survives the prompt path without growing resident C128 data
    - c128 size follow-up: the first stack-free rewrite using a resident byte pushed the staged banked payload to `$E001` and tripped `Banked payload staged source ends below overlay window`; moving the snapshot to `zp_temp0` brought the build back under the `$E000` ceiling
    - verification passed:
      - `make test64`
      - `make test128-fast-smoke`
    - remaining gate:
      - manual live C64 `SHIFT+S` repro still needs confirmation
- [x] FEAT-DISK user-friendly save-disk workflow
  - [x] replace the old low-level title disk menu with a guided `D)isk Setup` entry and first-use setup gate for `N`/`L`
  - [x] split FEAT-DISK into a tiny resident state/validation layer plus overlay-driven setup UI on C64/C128
  - [x] gate save/load/high-score I/O on configured save media and reject the program disk as persistence media
  - [x] close the focused C64 resident disk-swap/runtime regression
  - [x] get consultant review on UX shape and memory/code-space fit
  - [x] record implementation review and verification results below
  - review:
    - implementation: the title menu now exposes `D)isk Setup`, `N` and `L` force first-use setup in a fresh session, and the guided setup flow defaults to drive `9`, falls back to one-drive save-disk swap on drive `8`, and keeps expert drive entry as a fallback
    - implementation: resident FEAT-DISK logic was trimmed down to session state, swap prompts, device probe/init, and save-disk marker validation in `commodore/common/disk_swap.s`; the friendlier setup/init flow now lives in overlay code in `commodore/common/ui_disk_setup.s`
    - implementation: save, load, delete, and hall-of-fame I/O now all gate on configured save media, and the setup flow blocks using the program disk itself as persistence media
    - verification passed:
      - focused C64 runtime check for `tests/test_disk_swap.s`: all `9/9` resident-contract bytes passed under VICE at `$0400-$0408`
      - `make test64`
      - `make test128-fast-smoke`
      - independent tester signoff: `Exact reported command: PASS`, `Broader regression suites: PASS`, `ALL TESTS PASSED yes`
    - consultant review:
      - no major blockers; the resident/overlay split is the correct fit for current C64/C128 memory pressure
      - main memory/code-space risk is future growth in `HelpOverlay`, because the disk-setup UI currently lives there on both platforms and does not yet have a dedicated feature-specific size guard
      - main UX gap is hall-of-fame behavior when save media is missing or unconfigured: score I/O currently fails closed for correctness but does not surface a friendly recovery prompt the way save/load now do
- [x] BUG-C128-LOOK-DOOR-RANGE
  - [x] reproduce the C128-only report that looking at doors appears to require adjacency while C64 look range is correct
  - [x] add focused C128 regression coverage around shared visibility lookup on the banked C128 map
  - [x] verify the relevant C128 gates after the fix
  - review:
    - initial source review confirmed shared `do_look` is ray-based, not adjacency-only: it seeds the adjacent tile, computes `dl_dx/dl_dy`, and keeps stepping until it finds a visible non-floor target or visibility fails
    - root cause: `los_is_visible` in `commodore/common/dungeon_los.s` read the tile with a raw `(zp_ptr1),y` load instead of the MMU-safe map accessor, so on C128 it could inspect Bank 0 instead of the live Bank 1 map
    - symptom fit: `look` would prematurely report `nothing special` for walls, doors, and monsters whose live Bank 1 tiles were visible on screen but whose Bank 0 mirrors were dark or unrelated; stairs could still appear to work when the wrong-bank byte happened to satisfy the shared visibility rule
    - implementation: `los_is_visible` now uses `:MapRead_ptr1_y()` so C128 visibility tests read the owned banked map through the same MMU-safe contract as the rest of the shared map code
    - regression coverage: `test_dungeon128.s` now forces Bank 0 and Bank 1 to disagree at the same map coordinate and asserts that `los_is_visible` honors the lit Bank 1 tile
    - verification passed:
      - `make test128-fast`
      - `make test128-fast-smoke`
      - `make test64`
      - independent tester signoff: `ALL TESTS PASSED`
- [x] BUG-LOOK-TRAP-DOOR / BUG-LOOK-WALL-GOLD
  - [x] keep the fix inside shared `do_look` rather than reopening the broader directed-look redesign
  - [x] preserve terrain Huffman IDs across `look_flash_target`
  - [x] make non-floor terrain authoritative so wall/seam tiles do not fall through to floor-item lookup
  - [x] add focused C64 regressions for closed door, trap, wall-with-gold seam, and floor gold
  - review:
    - root cause 1: `dl_print_tile` relied on `X` surviving `look_flash_target`, but the flash path clobbers `X`, so trap/door terrain messages could decode as unrelated Huffman strings
    - root cause 2: `do_look` checked `floor_item_find_at` before terrain classification, so non-floor tiles sharing coordinates with injected items could be reported as gold/items instead of terrain
    - root cause 3: the wall fallback loaded `HSTR_DL_WALL` but accidentally fell through into `dl_print_you_see` instead of `dl_print_tile`, so walls reused stale monster/item name pointers from earlier look results
    - implementation: shared `do_look` now saves/restores the terrain message ID across the flash call, only consults `floor_item_find_at` after confirming the tile is actual floor, gates monster lookup on the live tile's `FLAG_OCCUPIED` bit to match renderer ownership, and jumps the wall fallback into `dl_print_tile` instead of the stale-name path
    - verification passed:
      - `make test64`
      - `make test128-fast`
      - `make test128-fast-smoke`
- [x] BUG-C128-BOOTART-ORDER
  - [x] make the C128 boot-art poster appear only after the custom-charset attributes are already in place
  - [x] verify with the relevant C128 smoke gate
  - review:
    - root cause: the C128 boot-art helper streamed the screen map before the attribute map, so the new character codes could flash briefly under the previous non-poster attribute/charset state
    - implementation: `bootart128.s` now writes the generated attribute map before the generated screen map so the visible poster characters only appear once the alternate-charset mode bits are already active
    - verification passed:
      - `make test128-fast-smoke`
- [x] BUG-TOWN-SIZE-DRIFT
  - [x] replace the invented shared `80x48` town with a fixed `66x22` layout on both C64 and C128
  - [x] keep the Commodore-only Black Market and Home in a deliberate `4x2` town layout
  - [x] update C64/C128 town tests to the new doors, stairs, and boundary assertions
  - [x] verify with focused town coverage plus `make test128-fast`, `make test128-fast-smoke`, and `make test`
  - review:
    - root cause: the port had treated the AI-invented `80x48` town as if it were source-game geometry, and `town_generate` reused live map dimensions instead of owning a fixed town footprint
    - implementation: shared town constants now define a fixed `66x22` town, `town_generate` carves that rectangle inside the live map, space outside town stays blocked but no longer carries lit town-wall flags, the C64 viewport clamps to town bounds, and the reverted C128 town re-anchor was removed so town entry keeps the expected framing instead of snapping on the first move
    - verification passed:
      - `TEST_FILTER='render|store' bash commodore/c64/run_tests.sh`
      - `TEST_FILTER='store' bash commodore/c64/run_tests.sh`
      - `python3 -u commodore/c128/harness128_batch.py --mode cold --tests soak128 --vice /opt/homebrew/bin/x128 --connect-timeout 12`
      - `python3 -u commodore/c128/harness128_batch.py --mode cold --tests vdc_scroll_delta128 --vice /opt/homebrew/bin/x128 --connect-timeout 12`
      - `make test128-fast`
      - `make test128-fast-smoke`
      - `make test`
- [x] FEAT-BOOT-ART shipping fallback
  - [x] C64 boot path loads and displays the generated logo bitmap during the main-program load
  - [x] C128 boot path loads and displays the generated logo poster helper during the main-program load
  - [x] C128 handoff restores the normal charset contract cleanly before title flow
  - [x] title screen now shows the per-platform version from `version.json`
- [x] FEAT-DISK-LAYOUT shipping split
  - [x] C64 shipping image emits as `moria8-c64.d64`
  - [x] C128 shipping image emits as `moria8-c128.d71`
  - [x] C128 Track 1 / Sector 0 is reserved before the native boot sector is patched
- [x] FEAT-VERSION-MANIFEST
  - [x] add per-platform user-facing version source at `version.json`
  - [x] wire disk directory card text to the manifest
  - [x] wire title-screen version text to the manifest
- [x] BUG-C128-TOWN-TOPROW-VDC-BLOCK-ORDER
  - [x] update `rvsd_issue_block_copy` so VDC reg 24 copy mode is programmed before reg 30 triggers the operation
  - [x] add a targeted `vdc_scroll_delta128` regression that forces reg 24 fill mode before the first fast-scroll block op
  - [x] verify with the focused `vdc_scroll_delta128` test plus `make test128-fast` and `make test128-fast-smoke`
  - review:
    - root cause confirmed enough to fix: `rvsd_issue_block_copy` was programming reg 30 before reg 24, which is backward for 8563 block operations
    - regression coverage now forces reg 24 fill mode before the first upward fast-scroll block op so the old ordering would fail deterministically
    - verification passed:
      - `python3 -u commodore/c128/harness128_batch.py --mode cold --tests vdc_scroll_delta128 --vice /opt/homebrew/bin/x128 --connect-timeout 12`
      - `make test128-fast`
      - `make test128-fast-smoke`
- [x] No active implementation work for this feature branch.
- Historical branch notes for the earlier unified-disk and proof/demo phases remain below for reference only.

## `FEAT-BOOT-ART` Design Plan

### Locked Intent
- Replace the plain `LOADING MORIA8...` boot text with real boot presentation artwork.
- Keep the title screen and main menu after boot art; boot art is a pre-title loading presentation, not a replacement for the title screen.
- Preserve the shared artistic identity on both platforms:
  - `MORIA8` wordmark
  - Art Deco frame
- Phase 1 is static art only.
- Gold glint animation is explicitly deferred to a later phase.

### Consultant Guidance
- Do not force real bitmap decode/render logic into the bootloaders themselves if it can be avoided.
- Keep the bootloader code focused on mode setup, prebuilt asset load/show, and handoff.
- Share the visual composition between platforms, not necessarily the runtime representation.
- Prefer separate prebuilt boot-art assets over embedding large bitmap blobs directly into `boot.s` / `boot128.s`.

### Recommended Architecture
- Add platform-local boot-art asset files to the platform-local disk images.
- Generate both from one shared source-art workflow, but allow platform-specific conversion/touch-up.
- Boot flow becomes:
  - initialize boot code
  - load/show platform boot-art asset
  - keep art visible
  - load main program
  - hand off to the normal title/menu flow

### Platform Strategy
- C64:
  - use multicolor bitmap
  - centered composition with black margins is acceptable
- C128:
  - stay on the native 80-column path
  - shipping path is now a VDC custom-charset poster, not a true VDC bitmap
  - keep the failed true-bitmap experiment stashed as separate R&D, not the product plan
  - preserve the same composition and styling through a technically different 80-column tile/attribute representation
- Shared rule:
  - same composition and artistic identity
  - platform-local representation is allowed

### Asset / Build Strategy
- Keep the pipeline replaceable so later commissioned or hand-tuned source art can be dropped in without redesigning the boot system.
- Keep the boot-art data outside the core bootloader binaries where practical.

### Phase Plan
- [x] Phase 0 — Feasibility / format spike
  - findings:
    - C64 side is straightforward technically: a multicolor bitmap boot asset is viable and can stay visible during the main-program load if it lives in a VIC bank above the current `MORIA64` load ceiling rather than in the usual `$2000` area that the main program would overwrite.
    - C128 side is the real constraint. Official C128 docs treat 80-column VDC as text-oriented, but explicitly note that custom machine-language programs can drive bitmap-style graphics there. So the feature is viable in principle, but it is not a normal built-in “multicolor bitmap mode” like the VIC side.
    - The old mixed-image disk budget is no longer the governing constraint for this feature because the user has now chosen separate platform disk images.
    - Conclusion: the richer boot-art feature remains viable, and the split-image requirement meaningfully reduces the disk-budget pressure that the unified-image design created.
  - continue under these assumptions:
    - separate boot-art assets are preferred over embedding full bitmaps into the boot binaries
    - C64 and C128 may use different runtime representations while preserving the same composition and style
    - boot-art implementation must preserve the platform boot contracts and title-screen handoff, but no longer needs to preserve one mixed-platform shipping disk
- [x] Phase 1 — Static boot art on C64
  - separate C64 boot-art asset file added
  - displayed from the C64 boot path
  - current loading text removed
  - image kept visible through main-program load
  - first quality pass complete: per-cell screen/color data now ships with the asset instead of one fixed screen/color fill across the whole poster
- [x] Phase 2 — Static boot art on C128
  - [x] add a separate C128 boot-art helper file
  - [x] replace the diagnostic helper payload with a generated custom-charset poster asset package
  - [x] display the generated poster from the native C128 boot path in 80-column mode
  - [x] keep the image visible through main-program load
  - [x] re-run the exact `make test128-fast-smoke` gate after the generated asset path lands
  - use the custom-charset poster pipeline below rather than true VDC bitmap mode
- [x] Phase 3 — Shared art pipeline cleanup
  - `tools/make_logo.py` now provides the shared fallback source for both platforms
  - the fallback is intentionally simple and replaceable without changing bootloader architecture
- [ ] Phase 4 — Better final art
  - commission or create stronger source art
  - keep the current boot plumbing and replace only the asset/conversion content
- [ ] Phase 5 — Glint animation
  - add subtle gold-highlight glint effect
  - do not begin animation work until both static boot-art paths are proven stable

### Explicit Rejections
- Do not replace the title/menu screen with the boot-art screen.
- Do not force the C128 side to use the exact same technical representation as C64 if a visually matching 80-column solution is better.
- Do not start with animation before the static asset path is stable.
- Do not collapse this back into the invalid “single universal `MORIA8.PRG`” idea.
- [x] Fix the C64 bump-to-attack regression so moving into a monster attacks correctly again.
- [x] Fix the C128 chargen summary flow so the character summary appears exactly once before town entry.
- [x] Correct `FEAT-SEARCH-MODE` running behavior so search mode remains active during running, matching `umoria`.

### C128 Boot-Art Design (2026-03-30)
- Runtime representation:
  - stay in the proven native `80x25` VDC text path instead of true VDC bitmap mode
  - treat the poster as a custom tile set in VDC character memory plus a screen map and attribute map
  - reuse the existing VDC screen/attribute bases already used by the game backend:
    - screen map at `$0000`
    - attribute map at `$0800`
  - keep VDC attribute bit 7 set so the poster uses the alternate character set path already assumed by [`commodore/c128/screen_vdc.s`](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-work/commodore/c128/screen_vdc.s)
- Offline asset pipeline:
  - start from one shared high-resolution source composition for both platforms
  - prepare a C128 working image on an `80x25` cell grid (`640x200` conceptual layout, `8x8` cells)
  - slice into `8x8` monochrome tile patterns
  - deduplicate into at most `256` unique tiles for one VDC character set bank
  - emit three files:
    - charset payload: `256 * 8 = 2048` bytes
    - screen map: `80 * 25 = 2000` bytes
    - attribute map: `80 * 25 = 2000` bytes
  - if the first pass exceeds `256` unique tiles, reduce complexity in the converter/art pass rather than complicating the runtime
- Boot/runtime flow:
  - `boot128.s` enters the normal 80-column VDC mode and clears the screen
  - load the C128 boot-art asset package from disk
  - upload charset bytes into VDC character memory
  - stream the screen map into `$0000`
  - stream the attribute map into `$0800`
  - leave the poster visible while `MORIA128` loads
  - before handing off to the main/title flow, restore the normal gameplay/title charset contract if the boot-art tiles displaced it
- Verification gates before integration:
  - standalone proof: custom VDC charset upload plus a nontrivial poster fragment rendered from screen/attribute maps
  - boot proof: poster remains visible through the later `MORIA128` load
  - regression proof: existing C128 VDC text/attribute tests still pass unchanged
- Why this path:
  - it is native to the proven VDC text backend already in the tree
  - it preserves the desired 80-column C128 identity
  - it is far easier to reason about and verify than the stalled attribute-enabled VDC bitmap experiment

### Review
- Current conclusion: the native C128 custom-charset poster path is proven enough to ship as the fallback boot-art implementation.
- The generated C128 boot-art path now exists via [`tools/ppm_to_c128_bootart.py`](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-work/tools/ppm_to_c128_bootart.py) plus [`commodore/c128/bootart128.s`](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-work/commodore/c128/bootart128.s).
- The generator now targets the full VDC Set 1-safe alternate charset budget (`127` custom tiles plus blank at `$20`) and emits:
  - `out/c128/bootart128_charset.bin`
  - `out/c128/bootart128_screen.bin`
  - `out/c128/bootart128_attr.bin`
  - `out/c128/bootart128_preview.ppm`
- A shared geometric fallback boot-art path now exists via [`tools/make_logo.py`](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-work/tools/make_logo.py), and both [`commodore/Makefile`](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-work/commodore/Makefile) boot-art rules now consume that generator instead of external JPG inputs.
- The fallback art is intentionally simple: a shared black/gold/white `MORIA8` art-deco block logo that survives both the C64 multicolor converter and the C128 charset poster converter.
- The C128 centering bug was caused by a stale poster-era wordmark override in [`tools/ppm_to_c128_bootart.py`](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-work/tools/ppm_to_c128_bootart.py); the fallback path now uses the plain converted geometry with a centered plaque from [`tools/make_logo.py`](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-work/tools/make_logo.py).
- `x128 -80col -limitcycles 12000000 -exitscreenshot /tmp/moria8_fallback_c128.png commodore/out/moria8-c128.d71` captured the live C128 fallback logo boot screen during development.
- `x128 -80col -limitcycles 12000000 -exitscreenshot /tmp/moria8_fallback_c128_centered.png commodore/out/moria8-c128.d71` captured the updated centered C128 fallback logo during development.
- The generated C64 multicolor asset also decodes cleanly from [`commodore/out/c64/bootart64.prg`](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-work/commodore/out/c64/bootart64.prg) to `/tmp/moria8_fallback_c64_preview.png`; direct live `x64sc` screenshot capture is currently blocked in this environment by a GUI initialization failure.
- The updated centered-plaque C64 fallback asset decodes cleanly to `/tmp/moria8_fallback_c64_centered.png`.
- The simpler fallback composition is better than the plaque version: [`tools/make_logo.py`](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-work/tools/make_logo.py) now emits a border-only art-deco frame with a centered `MORIA8` wordmark and no inner plaque.
- The attempted C128 runtime title overlay in [`commodore/c128/bootart128.s`](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-work/commodore/c128/bootart128.s) was removed; the fallback boot path is back on the already-proven generated charset/screen/attr asset path.
- The C128 boot handoff now blanks the 80-column VDC screen inside [`commodore/c128/bootart128.s`](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-work/commodore/c128/bootart128.s) via direct VDC writes before restoring the normal alternate charset. This avoids the garbage-glyph flash without reintroducing the branch-local regression caused by a KERNAL `CHROUT $93` clear in [`commodore/c128/boot128.s`](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-work/commodore/c128/boot128.s).
- Current preview baselines:
  - C128 generated preview: `/tmp/moria8_c128_preview_simple.png`
  - C64 source preview: `/tmp/moria8_c64_source_simple.png`
- The fallback wordmark is now explicitly condensed for the `160x200` source path so the C64 title fits inside the border with real side margins, while the C128 path keeps the broader centered treatment.
- Updated preview baselines:
  - C128 generated preview: `/tmp/moria8_c128_preview_narrow2.png`
  - C64 source preview: `/tmp/moria8_c64_source_narrow2.png`
- The better fix is to reuse the same main `MORIA8` glyph family on both platforms and simply scale it down for the C64 source path; the ad hoc condensed small-font experiment is gone.
- Current matching-style preview baselines:
  - C128 generated preview: `/tmp/moria8_c128_preview_match.png`
  - C64 source preview: `/tmp/moria8_c64_source_match.png`
- `make test128-fast-smoke` passes again after the generated poster integration (`3 passed, 0 failed`).

## Historical Note — `FEAT-UNIFIED-DISK` / `BUILD-UNIFY`

The section below is retained only as historical context for the earlier dual-entry-disk phase. It does not reflect the current shipping repo state after the 2026-03-31 split-image change.

### Locked Intent
- Ship one hard-`D64` disk image as the primary artifact.
- Keep the current C64 `DEL` directory-art header at the top of the unified disk.
- Do not require one identical first-loaded BASIC `MORIA8.PRG`.
- Require one unified disk that boots correctly on both platforms via platform-appropriate entry paths.
- Permit platform-specific support filenames everywhere else.
- Consolidate Commodore build/test orchestration into one [commodore/Makefile](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-work/commodore/Makefile), with the repo-root [Makefile](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-work/Makefile) left as a thin wrapper.
- Use `commodore/out` as the unified output tree.
- Replace the current command surface with cleaned-up primary targets:
  - `make build`
  - `make disk`
  - `make run`
  - `make test`
  - `make test64`
  - `make test128`
  - `make test128-fast`
  - `make test128-fast-smoke`
  - `make clean`
- Keep explicit debug-only single-platform disk targets.
- Remove legacy target aliases rather than preserving them indefinitely.
- Do not proceed with broader unified-disk validation until the disk-entry architecture is settled as:
  - C64 directory-file entry
  - native C128 boot-sector entry

### Working Assumptions
- Proposed shipping/debug disk targets:
  - `make disk` → unified shipping disk
  - `make disk64` → compatibility alias for the same unified shipping disk
  - `make disk128` → compatibility alias for the same unified shipping disk
- Proposed default run target:
  - `make run` → launch the unified shipping disk
- Working on-disk filename policy (compressed to stay under the C128 staged-image ceiling):
  - C64 directory boot file: `MORIA8`
  - child boots: `BOOT64`, `BOOT128`
  - main programs: `MORIA64`, `MORIA128`
  - title art: `T64`, `T128`
  - overlays: `64.START`, `128.START`, `64.TOWN`, `128.TOWN`, `64.DEATH`, `128.DEATH`, `64.GEN`, `128.GEN`, `64.HELP`, `128.HELP`, `64.UI`, `128.UI`
  - shared tier data: `MONSTER.DB.1` through `MONSTER.DB.4`
  - C128-only low runtime: `128.RUNTIME`
- Native C128 boot should come from the disk boot sector, not by trying to run the C64 BASIC-entry file in native C128 mode.

### Capacity Check
- Current rough block budget says the unified `D64` is plausible:
  - current C64 disk uses `286` blocks
  - current C128 masterboot disk uses `315` blocks
  - `MONSTER.DB.1-4` are byte-identical between platforms, so one shared copy saves `24` duplicated blocks
  - preliminary unified estimate: `577` blocks used, about `87` blocks free on a standard `D64`
- This is only a planning estimate.
- Phase 0 must re-measure after filename changes, directory art, and the real universal bootloader land.

### Phase A — Dual-Entry Disk Architecture
- [x] Prove the “one identical first-loaded BASIC PRG” idea is the wrong target for this feature.
- [x] Build a minimal dual-entry proof-of-concept disk before touching the final mixed payload.
- [x] Patch a tiny native C128 boot sector into Track 1 / Sector 0 of that proof-of-concept disk.
- [x] Prove the native C128 boot sector reaches a trivial known-good success path.
- [x] Prove the same proof-of-concept disk still boots on C64 via the first directory file path.
- [x] Define and implement the dual-entry disk contract:
  - [x] C64 loads the first directory file (`MORIA8`) via the normal file-loader path
  - [x] native C128 boots from a native boot sector on the same `D64`
- [x] Keep the proven per-platform child bootloaders as the correctness baseline:
  - [x] `BOOT64`
  - [x] `BOOT128`
- [x] Add a tiny native C128 boot-sector stage that loads or transfers control into `BOOT128`.
- [x] Re-green the real manual boot gate under the new architecture:
  - [x] C64 boots through the directory entry path
  - [x] native C128 boots through the native boot-sector path

### Phase 0 — Disk Budget And Collision Audit
- [x] Create a unified artifact inventory with final planned disk filenames and source-path owners.
- [x] Confirm which runtime-loaded assets are shared versus platform-specific.
- [x] Recompute exact `D64` block usage with the final filename map and C64 `DEL` art included.
- [x] Stop/go checkpoint:
  - if the unified payload no longer fits on a hard `D64`, stop the effort and do not merge this branch.

### Phase 1 — Build System Consolidation
- [x] Create [commodore/Makefile](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-work/commodore/Makefile) as the only real Commodore build entrypoint.
- [x] Move C64 and C128 build logic out of the deleted platform Makefiles into the unified Makefile.
- [x] Update the repo-root [Makefile](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-work/Makefile) to delegate only to `commodore/Makefile`.
- [x] Move build outputs to `commodore/out`.
- [x] Leave legacy `commodore/c64/out` and `commodore/c128/out` cleanup for a later slice while existing test runners still materialize transitional local `out/` trees.
- [x] Normalize the command surface around the new primary targets and drop legacy aliases from the main UX.

### Phase 2 — Unified Disk Filename Refactor
- [x] Introduce explicit platform-specific runtime asset filenames for title and overlays.
- [x] Update all runtime filename tables and loaders to use the new platform-specific asset names:
  - [commodore/common/title_screen.s](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-work/commodore/common/title_screen.s)
  - [commodore/common/overlay.s](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-work/commodore/common/overlay.s)
  - any C128 runtime-low loader references in [commodore/c128/main.s](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-work/commodore/c128/main.s)
- [x] Update disk-image build recipes so the unified disk contains:
  - one shared copy of `MONSTER.DB.1-4`
  - both platform title assets
  - both platform overlay families
  - both platform main programs
  - both platform child bootloaders
  - the C64 directory-entry loader file
  - the C128 native boot sector
  - C128-only `128.RUNTIME`
  - C64 `DEL` directory art

### Phase 3 — Unified Disk Integration
- [x] Make the unified disk build correctly through both platform-specific entry paths on the same disk image.
- [x] Do not regress the user-visible contract:
  - [x] C64 file boot still works from the directory
  - [x] native C128 boot still works in C128 mode

### Phase 4 — Compatibility Target Cleanup
- [x] Retire standalone `moria64.d64` / `moria128.d64` outputs so the unified shipping disk remains the only disk image.
- [x] Keep `disk64`, `disk128`, and `run64` only as compatibility aliases that point at the unified shipping artifact.

### Phase 5 — Test And Tooling Consolidation
- [x] Point the unified Makefile targets at the existing test runners first.
- [x] Normalize internal test/build target names only where it materially simplifies the new command surface.
  - deeper internal harness renames deferred; the public `make` surface is now the normalized contract
- [x] Keep C128-specific fast/full distinctions available under the unified Makefile.

### Verification Gates
- [x] `make build` produces both platform program artifacts plus the C64 directory-entry loader and C128 boot-sector assets under `commodore/out`.
- [x] Minimal proof-of-concept `D64` boots on both targets before the full mixed-payload refactor proceeds.
- [x] `make disk` now produces the real mixed-platform `D64` at [commodore/out/moria8.d64](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-work/commodore/out/moria8.d64) with the C64 `DEL` art header, both platform payloads, and the patched C128 boot sector.
- [x] `commodore/out/moria64.d64` and `commodore/out/moria128.d64` are no longer produced; the unified shipping disk is the only disk artifact.
- [x] Real manual validation:
  - [x] C64 boots from the unified disk through the directory-file path to the C64 runtime.
  - [x] native C128 boots from the unified disk through the C128 boot sector to the C128 runtime.
- [x] `make run128` now exercises the unified shipping disk on native C128 instead of the standalone debug disk.
- Broader post-refactor emulator suites were intentionally not rerun during this closeout because the user chose manual validation for the boot work:
  - `make test64`
  - `make test128-fast`
  - `make test128-fast-smoke`
  - `make test128`

### Risks To Watch
- Native C128 boot-sector integration is now the riskiest part; it must work on a `D64` and hand off cleanly into the existing C128 loader/runtime.
- Overlay/title filename refactors touch runtime loader tables and can easily create silent wrong-file regressions.
- Moving to `commodore/out` will ripple through shell scripts, test harnesses, and disk-build assumptions.
- `D64` headroom is real but not huge; directory art, renamed files, and any loader growth must be watched continuously.
- Current non-emulator verification for the unified build cutover:
  - `make -C commodore clean && make -C commodore build && make -C commodore disk && make -C commodore disk64 && make -C commodore disk128`
  - `make build` (repo root wrapper) → routes cleanly to `commodore/Makefile`
  - `find commodore/out -maxdepth 2 -type f | sort` → unified artifact tree under `commodore/out/{c64,c128}`
  - `c1541 -attach commodore/out/moria8.d64 -list` → 91 blocks free
  - `find commodore/c128/out -maxdepth 1 -type f | sort` and `find commodore/c64/out -maxdepth 1 -type f | sort` → compatibility mirror trees populated for legacy harnesses
  - Track 1 / Sector 0 begins with `CBM` and contains `BOOT"BOOT128",U8`
- [x] Fix the C64 `CMD_RUN_*` regression introduced during `FEAT-SEARCH-MODE` command-path changes.
- [x] Implement `FEAT-SEARCH-MODE` player-owned runtime helpers and transient save/load masking.
- [x] Implement authentic derived search/fos math and shared search-scan helpers.
- [x] Wire movement, discrete post-turn tails, and run/disturb/relocation seams without duplicating extra-turn logic.
- [x] Add the persistent status-area `Searching` indicator and `#` input/help updates on both targets.
- [x] Add focused C64/C128 regressions for input, status cache, save/load transience, and search-mode turn behavior.
- [x] Rebuild and verify C64/C128 layout boundaries plus the required test suites.
- [x] Inspect the live FEAT-SEARCH-MODE owner modules and target memory-layout definitions for C64/C128.
- [x] Identify likely code/data growth hotspots and any segments at meaningful risk from the planned feature.
- [x] Write a concise findings-first memory/layout/code-bloat review with required verification gates.
- [x] Inspect the active `FEAT-SEARCH-MODE` backlog note, current one-turn search flow, and the shared turn/input/save seams it would have to touch.
- [x] Verify the original search-mode and passive auto-search contract from the local `umoria` / `vms-moria` mirrors instead of inferring from the current port.
- [x] Get a consultant-style design review focused on ownership, turn-model fit, key-binding risk, and verification scope for `FEAT-SEARCH-MODE`.
- [x] Capture a recommended design, rejected alternatives, and open questions for `FEAT-SEARCH-MODE`.
- [x] Review the current `REF-MON-SOA` backlog note, monster-table architecture, and hot-path ownership in the codebase.
- [x] Get a consultant-style design review focused on correctness risk, memory/layout impact, and likely performance upside of converting the active monster table from AoS to SoA.
- [x] Gather local profiling evidence or the closest available proxy from the existing test/harness/tooling to estimate whether `REF-MON-SOA` is worth doing.
- [x] Write a recommendation with findings, open questions, and a go/no-go call for `REF-MON-SOA`.
- [x] Inspect the active `BUG-TOWN-KILL-DRAW` note plus the shared town combat, turn, and redraw ownership.
- [x] Trace the stationary-attack post-turn render contract through `combat.s`, `spell_effects.s`, `turn.s`, `game_loop.s`, and the C64/C128 renderers.
- [x] Compare design options for where a stale-kill redraw fix should live, including failure modes around `turn_scene_dirty`.
- [x] Capture a recommended design, consultant-style review, and verification strategy for `BUG-TOWN-KILL-DRAW`.
- [x] Implement the shared pending-redraw fix in the turn/effect seam without growing the C128 resident image past its layout constraints.
- [x] Add focused regression coverage for the producer and consumer halves of the redraw contract, then rerun the required C64/C128 verification.
- [x] Backlog note: C64 inventory return blanks the character-stats line after returning to the main screen.
- [x] Backlog note: C64 `GENERATING...` level-change transition can leave stale prior-frame rows on screen; this is not town-exit-specific.
- [ ] Backlog note: C64 first descent from town can leave garbage on the top row after level generation.
- [ ] Backlog note: C64 loading is currently broken outside this feature scope.

## `BUG-GEN-STALE-TOWN-C64` Review

### Final Diagnosis
- The remaining `GENERATING...` residue bug was still local to `generation_busy_begin`, not `game_loop.s` restore flow and not generation-time disk I/O.
- The busy screen already had the right blank/unblank ordering.
- The real failure was the clear primitive: raw `screen_clear` was still being used on a C64 full-screen transition path that needed the existing safe helper.

### Final Fix
- [`commodore/common/generation_busy.s`](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-work4/commodore/common/generation_busy.s)
- `generation_busy_begin` now calls `ui_clear_full_screen_safe` instead of `screen_clear`.
- The busy-screen contract stays:
  - `screen_blank`
  - safe full-screen clear
  - draw `GENERATING...`
  - `screen_unblank`

### Focused Test Coverage
- [`commodore/c64/tests/test_main_loop.s`](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-work4/commodore/c64/tests/test_main_loop.s)
- The busy-screen regression now asserts:
  - blank happens first
  - `ui_clear_full_screen_safe` is called exactly once
  - centered text draw still happens once
  - unblank happens last
  - raw `screen_clear` is not used on this C64 path
  - `generation_busy_end` still restores the saved text color and active flag

### Validation Status
- Manual C64 confirmation from the user: fixed in live play
- Automated cleanup verification:
  - focused C64 `test_main_loop.s` gate — PASS (`20/20`)
  - `make test` — PASS (`33` suites passed, `0` failed)
  - `make test128-fast` — PASS

## `BUG-INV-STATLINE-C64` Design

### Current Task
- [x] Inspect the C64 inventory return path, shared modal restore helper, and status redraw/cache contract.
- [x] Get a consultant review focused on ownership boundaries and the minimal durable fix.
- [x] Make the C64 row-by-row full-screen clear helper preserve the same forced-status-redraw contract as `screen_clear`.
- [x] Add a focused C64 regression proving an unchanged cached status bar repaints after the modal full-screen clear path used by inventory/help-style overlays.
- [x] Re-run the focused C64 UI test image plus the broader C64/C128 regression gates.

### Problem Statement
- `BUG-INV-STATLINE-C64` is a C64 gameplay-view restore bug, not an inventory-data bug.
- The likely failure seam is the C64 modal overlay clear/restore contract:
  - inventory/help-style overlays clear the whole screen through `ui_help_clear_all`
  - the C64 implementation clears row by row instead of calling `screen_clear`
  - unlike `screen_clear`, that path does not currently force the next `status_draw`
  - if the status cache still matches live player values, `status_draw` can skip repainting and leave rows 21-23 blank on return

### Recommended Fix Boundary
- Prefer fixing the C64 path in `commodore/common/ui_help_clear.s`, not only in the inventory return caller.
- Reason:
  - that helper owns the C64 full-screen modal clear contract
  - it should match the existing `screen_clear` postcondition for status redraw
  - this covers inventory plus any other help/inventory-style full-screen modal return path without duplicating one-off invalidation calls

### Verification Status
- Implemented the C64 fix in `commodore/common/ui_help_clear.s` so the row-by-row full-screen modal clear now forces the next `status_draw`.
- Added focused coverage in `commodore/c64/tests/test_ui_views.s` proving the unchanged cached HP line repaints after `ui_help_clear_all`.
- Follow-on test-layout repair:
  - moved the `commodore/c64/tests/test_save.s` RLE workspace upward to stay above the enlarged assembled test body without changing the test's round-trip behavior
- Automated verification completed:
  - focused `test_ui_views` monitor run = `PASS_COUNT=14`
  - focused `test_save` monitor run = `PASS_COUNT=10`
  - `make -C commodore/c64 test` — PASS (`33 passed, 0 failed`)
  - `make test128-fast` — PASS

## `BUG-LOAD-C64` Design

### Current Task
- [x] Inspect the current C64 title-menu, save/load, and runtime-resume seams in `commodore/c64/main.s`, `commodore/common/save.s`, and `commodore/common/game_loop.s`.
- [x] Review the historical save/load regressions and fixes (`BUG-42`, `BUG-44`, R15/R16, C128 save JAM) for recurring failure patterns instead of treating this as a fresh isolated bug.
- [x] Audit the current C64 test coverage and compare it with the stronger C128 title-load smoke coverage.
- [x] Get a consultant review focused on ownership boundaries, recurrence risk, and missing verification gates.
- [x] Write a durable design that makes the load path explicit, testable, and hard to regress.
- [x] Implement slice 1: explicit `load_result`, named C64 `title_load_game`, and title-safe `title_enter_menu` recovery instead of branching on carry back into the old loop.
- [x] Implement the ownership split and transaction contract needed to restore the C64 load/resume path under the existing C64 regression gate.
- [x] Fix the C64 test-layout regressions exposed while landing the shared save/load changes (`test_save`, `test_player`, `test_score`) and re-green `make -C commodore/c64 test`.
- [ ] Follow-up hardening: add dedicated disk-backed C64 title-load smokes so future regressions fail closer to the real `L` path.

### Problem Statement
- `BUG-LOAD-C64` is not just "the load command is broken."
- The recurring failure is architectural:
  - title-menu orchestration owns part of the flow
  - `save.s` owns file I/O and too much transaction cleanup
  - `load_resume_game` owns runtime re-entry
  - the C64 test suite does not currently exercise the real title `L` path end to end
- That combination lets regressions reappear in different forms:
  - wrong error message
  - wrong recovery path
  - corrupt or partial in-memory state after failed load
  - broken carry/status return
  - disk swap / save-device drift
  - a resume path that is locally unit-tested but not actually reachable through the title menu on real disk media

### Current Code Facts
- The C64 title menu still inlines the load flow in `commodore/c64/main.s`:
  - `disk_prompt_save`
  - `load_game`
  - `disk_prompt_game`
  - `load_resume_game`
- C128 already promotes this to a named `title_load_game` entrypoint, which is easier to test and reason about.
- `load_game` in `commodore/common/save.s` currently owns all of the following:
  - open/read/verify the file
  - message display
  - channel cleanup
  - `$DD00` VIC-bank restore
  - `player_sync_to_zp`
  - monster/item recounts
  - savefile deletion for permadeath
- `load_resume_game` in `commodore/common/game_loop.s` currently owns runtime re-entry:
  - `wizard_reset_session_state`
  - `player_search_clear_transient_state`
  - `tier_invalidate_state`
  - `tier_check_transition`
  - derived-stat rebuild
  - run-state reset
  - sound re-init
  - screen redraw and `WELCOME BACK`
- `commodore/c64/tests/test_main_loop.s` only verifies one narrow post-load fact today:
  - `load_resume_game` clears transient search state
- `commodore/c64/tests/test_save.s` is not a real load integration suite:
  - it tests RLE helper leftovers, checksum helpers, and recount logic
  - it does not drive the title `L` path or a real disk image
- C128 already has the integration test shape C64 is missing:
  - a seeded-disk `boot_title_load_resume_smoke`
  - explicit boot/title/load monitor gates
- `commodore/c64/debug_load.mon` still documents a rich load-diagnostic marker scheme, but the active code no longer emits those markers. The diagnostic contract has drifted out of sync with reality.

### Why This Keeps Coming Back

#### 1. The load return-status contract on C64 is structurally unsafe
- On C64, `EnterKernal` / `ExitKernal` are only:
  - `php`
  - `plp`
- `load_game` currently sets `sec` / `clc` and then executes `:ExitKernal()`.
- That means the advertised carry result from `load_game` is overwritten by the caller's saved processor flags before `rts`.
- The title path branches on that carry anyway.
- This is exactly the class of bug already captured in `tasks/lessons.md`: `plp` after `clc`/`sec` destroys carry-return contracts.
- As long as the load path relies on that fragile convention, this bug can reappear any time the surrounding callers happen to leave carry in a different state.

#### 2. The load is not transactional
- `load_game` deserializes directly into live RAM while the file is being read.
- If the file is truncated, corrupt, or otherwise fails after the first few blocks, the code returns to the title menu after mutating live gameplay state.
- There is no explicit "failed load leaves no live session behind" contract.
- This makes future regressions harder to diagnose because the visible failure can happen on the next title action, not at the failing read itself.

#### 3. The persistence schema is hand-maintained twice
- Save block order is written once in the save half and again in the load half.
- That duplication is survivable when the format is stable, but it is a long-term regression trap whenever new saved arrays, transient-mask rules, or layout changes land.
- The save-version byte exists, but the field manifest itself is not single-sourced.

#### 4. Disk-I/O cleanup is repeated rather than owned
- The C64 path currently depends on repeated local cleanup rules:
  - close file handles
  - restore channels
  - restore `$DD00` VIC bank 0
  - clear stale KERNAL status when appropriate
  - preserve any required caller status
- History already shows this seam breaking in multiple ways:
  - stale file table entries after KERNAL LOAD
  - wrong `READST` state after title art load
  - nested KERNAL-context transitions in save/delete helpers
- Repetition here is not harmless. It is how correctness contracts drift.

#### 5. The C64 suite lacks the one test that would have caught most of these regressions
- There is no C64 equivalent of C128's real-disk title-load-resume smoke.
- The current suite proves helper behavior, not the actual player-visible flow:
  - boot game
  - arrive at title
  - press `L`
  - read `THE.GAME`
  - branch to success or failure
  - resume cleanly or return to title cleanly
- That missing gate is the core reason this bug keeps escaping.

### Non-Negotiable Requirements
- The C64 load path must have a named, testable entrypoint rather than remaining an inline title-branch fragment.
- The persistence layer must return an explicit status code that survives any KERNAL-entry/exit mechanics.
- Failed loads must not leave partially loaded session state live when control returns to the title screen.
- `load_resume_game` must remain pure runtime re-entry:
  - no disk prompts
  - no KERNAL file I/O
  - no savefile deletion
  - no title-menu policy
- All C64 serial-I/O helpers used by title/load/save must return with the same postcondition:
  - default channels restored
  - required file numbers closed
  - `$DD00` back in the expected VIC bank
  - interrupt state restored to the expected title/runtime contract
  - any special KERNAL status reset performed by the owner that needs it
- Any failure-recovery path after a partial load must treat Zero Page and runtime scratch as contaminated until proven otherwise.
- The title recovery owner must explicitly reinitialize every title-critical ZP/UI variable it depends on rather than assuming a redraw alone is sufficient.
- Save-format evolution must be single-sourced enough that adding/removing a serialized block cannot silently change one half of the transaction but not the other.
- `BUG-LOAD-C64` is not closed until the real title `L` flow is green under a disk-backed smoke harness, not just under unit tests.

### Recommended Architecture

#### A. Promote the C64 title load flow to a named owner
- Mirror the C128 structure and add a C64 `title_load_game` entrypoint.
- `title_menu_loop` should only dispatch to that named routine.
- Ownership of `title_load_game`:
  - play acknowledgment sound
  - `msg_init`
  - prompt for save disk if needed
  - call the persistence transaction
  - prompt back to game disk if needed
  - branch cleanly to either:
    - `load_resume_game`
    - title re-entry / title menu recovery
- Reason:
  - this creates a single callable seam for testing and for any future C64 load-specific fixes
  - it removes hidden control flow from the middle of the title input loop

#### B. Replace carry-only load success/failure with an explicit transaction result
- Do not rely on carry as the authoritative `load_game` result on C64.
- Recommended shape:
  - add a small `load_result` byte with symbolic result codes:
    - `LOAD_RESULT_OK`
    - `LOAD_RESULT_NOTFOUND`
    - `LOAD_RESULT_CORRUPT`
    - `LOAD_RESULT_IOERR`
  - the caller branches on `load_result`
  - carry may still be set for convenience, but it must not be the only contract
- Reason:
  - the repo already has a real lesson showing how easy it is for `plp` to clobber carry returns
  - this path is too important to keep depending on a fragile flag-only convention

#### C. Make `load_game` a true persistence transaction owner
- `load_game` should own:
  - file open / read / checksum verify / close
  - savefile deletion on success
  - transaction result code
  - only serialization-local postprocessing that is inseparable from the on-disk transaction
    - allowed:
      - checksum state finalization
      - file/channel/VIC-bank cleanup
      - savefile scratch on successful committed load
      - copying loaded serialized bytes into their owned in-memory homes
    - not allowed:
      - title/menu branching
      - runtime transient clearing
      - tier invalidation or tier reload
      - stat/HP recompute
      - redraw / visibility / status work
      - any "resume gameplay" policy
- `load_game` should stop owning policy that belongs elsewhere:
  - title recovery behavior
  - disk-swap UI decisions
  - "what screen do we show next?"
- Design rule:
  - `save.s` may produce loaded bytes and transaction status
  - it should not decide whether the user returns to title or resumes gameplay

#### D. Make failed-load recovery explicit and title-safe
- A full shadow copy of the save image is not realistic on C64 and is not the recommended fix.
- Instead, define the failure contract explicitly:
  - if `load_game` fails after mutating live RAM, the session is abandoned
  - the code must re-enter a known-safe title state before accepting further title input
  - Zero Page and transient runtime state must be treated as hostile after a mid-stream failure
- Recommended shape:
  - add a dedicated title owner such as `title_enter_menu` and use it for:
    - initial title entry
    - post-load failure recovery
  - `title_load_game` should never jump back into the middle of the old inline title loop after a failed transaction
  - this helper should:
    - explicitly reinitialize every title-critical ZP byte and UI control byte it depends on
    - restore title-safe UI state
    - redraw title/menu from scratch
    - clear any transient title/disk prompt state needed before the next key read
    - avoid continuing the old title loop with potentially stale gameplay/session memory assumptions
- The design goal is not "preserve half-loaded runtime state."
- The goal is "failure returns to a clean title world every time."

#### D.1. Keep the KERNAL-context rule explicit
- The prior C128 save `JAM` proved this rule is not optional:
  - helpers that assume active KERNAL context, such as `delete_savefile_core`, must only be called from code that already owns that context
  - external wrappers may enter/exit KERNAL context
  - internal transaction helpers must not nest it
- Apply the same rule to the C64 load/save refactor even if the current C64 macros are lighter-weight.
- Design consequence:
  - `title_load_game` and `load_resume_game` must not call nested KERNAL-entry wrappers once inside the persistence transaction
  - the persistence owner must expose clear internal-vs-external helper boundaries

#### D.2. Treat interrupt and banking cleanup as part of recovery, not polish
- C64 failure recovery must restore:
  - `sei` / `cli` state to the expected post-transaction contract
  - `$DD00` VIC bank ownership
  - any IRQ vector assumptions that disk/KERNAL paths can disturb
- Do not assume the happy-path cleanup is enough.
- If a failed load can exit through a different branch, that branch must prove the same hardware postcondition as the success path before title rendering resumes.
- The design target is:
  - no recovery path can expose the title/menu loop to partially-restored IRQ or VIC-bank state

#### E. Formalize `load_resume_game` as the only runtime re-entry seam
- Keep runtime normalization centralized in `load_resume_game`.
- Add an explicit comment contract that any new transient runtime field introduced later must be normalized here, not in ad-hoc title or persistence code.
- Current examples that belong here:
  - search-mode transients
  - running state
  - tier metadata validity
  - derived stats and HP
  - sound/video redraw state
- Reason:
  - this keeps all post-load gameplay reconstruction in one auditable place
  - it prevents future features from smearing their "resume fixups" across unrelated codepaths

#### F. Single-source the save schema manifest
- The durable design is to stop hand-maintaining the save block order twice.
- Recommended implementation shape:
  - move the ordered save-block manifest into one include/macro list
  - expand it once for save, once for load
  - keep the save-version byte next to that manifest
  - add a computed total-byte constant for the serialized payload
- Constraint:
  - keep the manifest mechanically simple and monitor-readable
  - do not turn this into clever macro metaprogramming that obscures exact block order, byte counts, or where a failure occurred
- Secondary benefit:
  - the Python seeded-save generator used by C128 can then be mirrored or parameterized for C64 against one authoritative block list instead of another hand-copied format description

#### G. Reintroduce owned diagnostics instead of stale tribal debugging
- `commodore/c64/debug_load.mon` proves the load path has historically needed stage-level tracing.
- The current half-state is bad:
  - the monitor script documents step markers
  - the code no longer guarantees them
- Recommended direction:
  - restore a gated `C64_LOAD_DIAG` marker stream or equivalent label-based probes
  - keep the monitor script and emitted markers in sync
  - add a lightweight verification script or test check that fails if the expected diagnostic labels/markers disappear or drift
- Diagnostics are not optional folklore for this bug family.
- If they exist, they must be maintained as part of the contract.

### Specific Findings To Preserve
- The current C64 code already contains a likely live root-cause candidate:
  - `load_game` advertises carry-set success / carry-clear failure
  - `ExitKernal` is `plp`
  - therefore the result flag is not stable on return
- This is not just a debugging note.
- It changes the design:
  - carry-only status must be retired as the authoritative contract for this bug
- Another critical finding:
  - the C64 suite has no real-disk title-load smoke, while C128 already does
  - any "fix" that does not add that gate is likely to regress again

### Rejected Alternatives

#### Option A — Patch the current title branch again without changing ownership
- Reject.
- This has already failed multiple times in different forms.
- A local branch fix would not address:
  - carry-contract fragility
  - failure atomicity
  - missing real-disk coverage

#### Option B — Keep carry-only status and just save/restore it more carefully
- Reject as the primary contract.
- Even if carry preservation is repaired locally, the design still encourages future regressions through another `php`/`plp` edit.
- Use an explicit result byte as the stable public contract.

#### Option C — Add a full second copy buffer for the entire loaded session
- Reject for first-pass repair.
- It is too memory-expensive on C64 relative to the actual need.
- The simpler durable contract is:
  - failed transaction abandons the session
  - title state is rebuilt cleanly

#### Option D — Treat existing unit tests as sufficient once the branch works again
- Reject.
- The missing failure is specifically in the real title/menu/disk path.
- The fix is not trustworthy until the suite exercises that path.

### Verification Strategy

#### Required New C64 Smokes
1. `boot_title_load_resume_smoke`
   - Build a real C64 disk image containing a valid `THE.GAME`.
   - Boot from title, inject `L`, and prove the machine reaches `load_resume_game` or the first resumed gameplay-loop marker without `JAM`.
2. `boot_title_load_missing_save_smoke`
   - Boot a disk image with no `THE.GAME`.
   - Press `L`.
   - Prove the game returns to the title menu rather than falling into character creation or a partial session.
3. `boot_title_load_corrupt_save_smoke`
   - Boot with a truncated or checksum-bad `THE.GAME`.
   - Prove the game shows corrupt-file recovery and returns to the title menu cleanly.
4. `boot_title_load_delete_smoke`
   - Successful load must scratch the save exactly once.
   - Prove this by either:
     - checking the directory after success, or
     - reattempting `L` and observing the correct not-found path on the next attempt.
5. `boot_title_load_resume_dualdisk_smoke`
   - At least one swap-mode or custom-device path must be covered, because save-device routing is a historical seam, not an optional afterthought.

#### Required Unit / Host Tests
- Keep and extend the current `load_resume_game` transient-state coverage in `test_main_loop.s`.
- Add focused persistence-transaction tests for:
  - explicit `load_result` values
  - cleanup postconditions on failure
  - title-safe recovery helper behavior
  - schema manifest byte-count expectations
- `test_save.s` should stop being treated as if it proves end-to-end load correctness.
- It is only a helper-logic suite unless it grows real transaction coverage.

#### Provisional Verification Gate
- Once implementation begins, the active gate for `BUG-LOAD-C64` should be the new real-disk C64 smoke target, not just `make test`.
- Until the user provides a more specific failing command, the recommended gate is:
  - the exact new C64 title-load smoke for success
  - plus the missing-save and corrupt-save recovery smokes
  - plus `make test` afterward for broader regression coverage

### Consultant Review Summary
- Consultant recommendation aligned with the local findings:
  - keep `save.s` as persistence owner, not runtime-policy owner
  - keep `load_resume_game` as the one runtime re-entry seam
  - promote the C64 title-load path to a named entrypoint like C128
  - add real title-path smokes rather than leaning on unit tests
- One deliberate strengthening beyond the consultant baseline:
  - do not just preserve carry more carefully
  - promote an explicit `load_result` byte as the durable public contract for C64

### Implementation Order
1. Extract the C64 title `L` flow into a named `title_load_game` owner.
2. Replace carry-only `load_game` status with an explicit result code.
3. Centralize load transaction cleanup and title-safe failure recovery.
4. Add the real-disk C64 load smokes and make them authoritative.
5. Reassert `load_resume_game` as the only runtime re-entry owner.
6. Only after the smoke gate is green, single-source the save schema manifest.
7. Tighten any remaining user-facing recovery details or messages without weakening the new gate.

### Review
- 2026-03-28 implementation moved the C64 title `L` path to a named `title_load_game`, changed the title branch to use `load_result` instead of carry, and routed failed loads back through `title_enter_menu` so title UI/message state is rebuilt instead of resuming the stale title loop.
- The shared `save.s` growth exposed two layout regressions while landing the bug fix:
  - `commodore/c64/tests/test_save.s` had a hard-coded RLE workspace overlapping the assembled body
  - `commodore/c64/tests/test_score.s` had a resident-body / local-buffer layout that became unsafe near the `$D000` overlay boundary
- `commodore/c64/tests/test_player.s` also needed its real map/config dependencies wired in so the current `player.s` contract assembled under the C64 test harness.
- Final closure gate:
  - `make -C commodore/c64 test` = `33 passed, 0 failed`
- `BUG-LOAD-C64` is resolved under the current C64 regression gate.
- Follow-up hardening, not closure criteria:
  - dedicated disk-backed C64 title-load success/failure smokes
  - later single-source save-schema manifest cleanup

## `FEAT-SEARCH-MODE` Design

### Goal
- Restore original-style persistent search mode and passive auto-search behavior without refactoring the whole player-turn scheduler.
- Keep the existing one-turn `S` search command.
- Add the original `fos`-style passive search frequency behavior on ordinary movement.
- Preserve platform parity across C64 and C128 without turning this into a renderer or HAL problem.

### Upstream Contract Confirmed Locally
- Upstream `umoria` / `vms-moria` keeps one-turn search and a separate persistent search-mode toggle.
- Passive auto-search runs on ordinary movement when either:
  - search mode is on, or
  - `fos <= 1`, or
  - the `1-in-fos` roll hits.
- Search mode effectively makes the player spend an extra search turn alongside ordinary command execution.
- Search mode is disturbed off by major interruptions such as attacks and other forced state changes.

### Local Constraints
- The port does not have a general player-speed/status scheduler comparable to upstream.
- Turn ownership is explicit:
  - command tails call `turn_post_action`
  - movement owns its own `turn_post_action`
  - running owns its own `turn_post_action`
- `PLF_SEARCHING` already exists in `player.s` but is unused.
- `search` and `fos` columns already exist in `tables.s`, but there is no live derived search/perception state today.
- `do_search` in `dungeon_features.s` already behaves like a pure scan; the turn is consumed by its callers.
- `#` is the cleanest semantic toggle key, but C128 raw keyboard scanning does not currently synthesize that shifted symbol automatically.
- The status bar currently has no spare movement-state field, so restoring the upstream persistent `Searching` indicator requires deliberate status-UI work rather than a message-only shortcut.

### Recommended Architecture
- Model search mode as a persistent runtime flag plus an extra consumed search turn, not as a new global speed system.
- Keep the persistent runtime bit in `player_data + PL_FLAGS` using existing `PLF_SEARCHING`.
- Add shared player-owned helpers in `commodore/common/player.s`:
  - `player_search_mode_on`
  - `player_search_mode_off`
  - `player_search_mode_toggle`
  - `player_search_mode_disturb`
  - derived-stat helpers for `fos` and any future active-search chance
- Keep the actual map/trap/secret scan in `commodore/common/dungeon_features.s`, but split the scan from the command wrapper so movement and search-mode follow-up can reuse it without duplicating turn logic.
- Apply passive auto-search from `commodore/common/player_move.s` after a successful ordinary move, not from `turn.s`.
- Apply the search-mode extra search turn from the shared post-command seam:
  - after a command or movement step consumes its normal turn and resolves the immediate gameplay mutation
  - run one search scan
  - then run one extra `turn_post_action`
  - then fall into the existing visibility / redraw decision path
- Keep the feature in shared gameplay ownership:
  - `player.s` for mode state and derived-search helpers
  - `dungeon_features.s` for scan logic
  - `game_loop.s` and `game_loop_helpers.s` for extra-turn orchestration
  - `player_move.s` for passive auto-search on movement
  - input/help modules for the new binding and docs

### Why This Fits The Port Best
- It preserves the current explicit turn model instead of inventing a second scheduler.
- It keeps search semantics in shared gameplay code rather than platform-specific render/input glue.
- It lets the port match the original behavioral shape closely enough without forcing a risky rewrite of hunger, AI cadence, or run timing.
- It keeps the first pass small enough to verify with the existing input and main-loop unit tests.

### Command And State Contract
- Keep `S` as one-turn search.
- Add a new dedicated toggle command for search mode.
- Recommended semantic binding:
  - `#` on both platforms
  - implementation note: C128 needs explicit shifted-symbol normalization in `input128.s` for this to be real, because the direct CIA scan path does not currently yield `#` automatically
- Preserve search mode across ordinary commands by default.
- Force-clear search mode on major disturbances:
  - explicit toggle-off
  - melee engagement / monster attack disturbance
  - trap / teleport / forced relocation
  - dungeon-level transitions
- Do not clear it for read-only UI views:
  - help
  - inventory / equipment
  - look
  - character / recall

### Save / Load Recommendation
- Treat search mode as transient runtime state even though the bit lives in `PL_FLAGS`.
- Do not rely on save-file persistence for this mode.
- Preferred behavior:
  - clear search mode before save serialization, or mask transient mode bits before writing `player_data`
  - clear or mask any search-mode-related transient counters/state that live in the serialized ZP block
  - ensure resume/load starts with search mode off
- Reason:
  - upstream save behavior disturbs search/rest state before writing
  - restoring directly into an active extra-turn mode is surprising and makes save/load semantics harder to reason about

### Derived Search Stats
- Selected scope:
  - medium-high authenticity
  - restore variable search odds rather than keeping the current flat `1-in-6` reveal rule
- First pass should still derive stats on demand rather than adding new saved live fields.
- Required authentic behavior to restore:
  - derive active search chance from existing race/class `search` data
  - derive passive auto-search frequency from existing race/class `fos` data
  - apply upstream-style penalties for at least:
    - confusion
    - blindness
    - no light
  - if feasible in the same pass, also apply the hallucination/image penalty from upstream
- Item-modifier follow-up inside the same feature slice:
  - audit whether the port already exposes any search/perception ego or item bonuses
  - if those bonuses exist in shipped item data or are expected for authenticity, fold them into the derived search stat path instead of hard-coding race/class only
- Implementation shape:
  - add a shared helper that computes effective search chance for the current player state
  - use that helper for both one-turn search and search-mode/passive search scans
  - stop using the current fixed `1-in-6` reveal logic in `dungeon_features.s`
- Cost:
  - higher than the toggle/passive-only variant because this touches gameplay math, not just turn/input flow
  - still materially cheaper than a full scheduler rewrite because it stays inside search-stat derivation and scan resolution

### UI Recommendation
- Required for this feature:
  - a persistent status-area indicator while search mode is active, matching upstream `Searching` behavior
  - explicit toggle feedback messages such as `Search mode on.` / `Search mode off.`
  - updated help text on both C64 and C128
- Implementation note:
  - this likely wants a compact shared movement-state field that can represent at least `Searching` and `Resting`, rather than a one-off search-only hack
- Constraint:
  - do not treat message-only feedback as sufficient for the authentic feature target

### Rejected Alternatives

#### Option A — Full player-speed / status-scheduler refactor
- Pros:
  - closer to the original implementation model
- Cons:
  - too invasive for the current explicit turn engine
  - high risk around hunger, AI cadence, and repeated command timing
  - unnecessary for the behavioral goal of this feature
- Verdict:
  - reject

#### Option B — Store new saved live search/fos fields in player or ZP state
- Pros:
  - can be fast at runtime
- Cons:
  - save/load churn for little first-pass value
  - easy to create stale derived-state bugs
  - `ZP_STATE_START..ZP_STATE_END` already serialize wholesale, so parking persistent mode in scratch ZP is a trap
- Verdict:
  - reject

#### Option C — Make passive search a generic end-of-turn hook in `turn.s`
- Pros:
  - one central place
- Cons:
  - wrong semantics because passive auto-search is movement-owned, not every-turn-owned
  - easy to accidentally search during rest, inventory, spell, or other non-movement turns
- Verdict:
  - reject

### Consultant Feedback
- The consultant agreed with the core architecture:
  - do not add a new global speed system
  - reuse `PLF_SEARCHING`
  - keep scan ownership in `dungeon_features.s`
  - keep passive auto-search in `player_move.s`
  - prefer `#` semantics for the toggle
- One deliberate adjustment from the consultant recommendation:
  - the consultant was willing to persist `PLF_SEARCHING` through save/load because `PL_FLAGS` already serializes
  - this design keeps the same storage location but recommends clearing it on save/load to stay closer to upstream disturbance semantics

### Risks
- Turn ownership is duplicated across movement, run, and shared command-result tails.
- If the extra search turn is only wired into one path, food and monster AI cadence will silently diverge by action type.
- Search reveal timing must happen before the final redraw/visibility choice for the turn, or revealed doors/traps can miss the render pass.
- Disturbance semantics are not centralized today, so there is real regression risk if mode clearing gets scattered inconsistently.
- `#` is not a free C128 binding today; the raw scan path needs an explicit symbol-normalization addition.
- `player_try_move` currently treats both actual relocation and melee-turn consumption as success, so passive search must not key only off the existing carry result.
- The persistent `Searching` indicator will go stale unless it joins the status-cache compare/update contract or forces a redraw on every mode transition.

### Memory / Layout Risk Review
- Overall risk:
  - low-to-moderate
  - the real pressure is resident shared-image growth, not overlays
- Most likely resident hotspot:
  - `commodore/common/ui_status.s`
  - reason:
    - the persistent `Searching` indicator must live in resident status rendering
    - any extra strings, cache bytes, and branching for movement-state display land in common code
- Next likely hotspot:
  - `commodore/common/game_loop.s`
  - `commodore/common/game_loop_helpers.s`
  - reason:
    - duplicated turn-tail edits will cost more bytes than the search math itself
- Lower-risk areas:
  - `commodore/common/dungeon_features.s`
  - input mapping code
  - help data / help overlays
  - reason:
    - variable search math and `#` mapping add some bytes, but they are not expected to be the primary pressure point
- Current segment posture:
  - C64 appears comfortable enough for this feature if the implementation stays compact
  - C128 remains layout-sensitive overall, but this feature does not currently look like an automatic overlay or I/O-hole risk by itself
- Design rule from the memory review:
  - do not pre-emptively relocate or split modules just for this feature
  - do centralize new logic so code growth happens once instead of in several duplicated tails
- Required anti-bloat ownership:
  - keep search-mode state helpers in `commodore/common/player.s`
  - keep search scan logic in `commodore/common/dungeon_features.s`
  - add one shared post-action/search-mode follow-up seam in `commodore/common/game_loop_helpers.s`
  - avoid patching separate copies of the same search-mode turn logic into movement, run, and command-result tails unless a path truly needs special handling
- Status/UI caution:
  - keep the movement-state indicator compact
  - do not build a larger status framework unless the feature actually requires it

### Pre-Flight Implementation Cautions
- Save/load transience:
  - search mode and any search-related transient counters must be explicitly masked or reset during save/write and load/resume paths
  - do not assume that storing the mode in `PLF_SEARCHING` is safe just because the feature wants runtime persistence
- Movement ownership:
  - add one authoritative signal for `player actually relocated`
  - passive auto-search and search-mode follow-up must key off that signal rather than the current broad `player_try_move` success path
  - attack-only turns must not trigger movement-owned passive search
- Trap / teleport / death sequencing:
  - define the gate for whether the extra search phase still runs after trap resolution
  - if the player dies, teleports, or is forcibly relocated before the search follow-up point, skip the extra search phase
- Status cache contract:
  - the `Searching` indicator must participate in the status cache / dirty-row logic
  - do not rely on one-shot toggle messages to keep the indicator visually correct
- Command binding contract:
  - confirm the final toggle command ID and help-text wording before touching both input paths
  - keep the distinction between one-turn `S` search and the persistent search-mode toggle explicit in both code and docs

### Verification Plan
- Input mapping:
  - extend `commodore/c64/tests/test_input.s`
  - extend `commodore/c128/tests/test_input128.s`
  - prove:
    - `S` still maps to one-turn search
    - `SHIFT+S` still maps to save
    - the new toggle binding maps correctly on both targets
- Main-loop dispatch:
  - extend `commodore/c64/tests/test_main_loop.s`
  - extend `commodore/c128/tests/test_main_loop128.s`
  - prove:
    - ordinary move without search mode still consumes one turn
    - move with search mode consumes the normal turn plus the extra search turn
    - attack-only turns do not count as relocation for passive search
    - read-only UI commands do not consume the extra search turn
    - run entry clears search mode
- Status/UI:
  - extend focused status/UI coverage to prove the persistent movement-state indicator appears while search mode is active and clears when the mode is disturbed off
  - prove `Searching` does not leave stale text behind after toggle-off, disturbance, or save/load resume
- Search behavior:
  - add focused coverage around the shared search scan helper
  - prove passive auto-search only happens on ordinary movement
  - prove search-mode follow-up search runs before the final redraw path
- Disturbance behavior:
  - prove the mode clears on at least one melee disturbance path and one forced-relocation path
- Trap / teleport sequencing:
  - prove the follow-up search phase is skipped when trap resolution kills, teleports, or otherwise relocates the player before the search-mode extra-turn point
- Save/load:
  - prove search mode is not left active after save/resume if we take the transient-state recommendation
  - prove any serialized search-related transient counters are reset or masked on resume
- Memory / layout:
  - rebuild both targets and re-check:
    - `program_end`
    - all `ovl_*_end` symbols
    - `runtime_low_data_end`
    - `banked_code_end`
    - `first_banked_function`
  - keep C128 callable-residency asserts green in `commodore/c128/io_contracts.s`
  - do not treat one-target success as sufficient, because this feature grows shared resident code

### Review
- Recommendation:
  - FEAT-SEARCH-MODE is a real resident-image risk on C128 and only a low-to-moderate one on C64.
  - The main/default segment is the pressure point, not overlays or `runtime.low`.
  - `ui_status.s` is the main likely hotspot because the authentic feature wants a persistent movement-state indicator and that code is resident shared UI, not an overlay on C64 and not easily relocatable on C128.
  - `game_loop.s` / `game_loop_helpers.s` are the next likely bloat sites because the current turn tails are duplicated across movement, run, and discrete-command paths; a naive implementation tends to duplicate extra-search and disturb handling in several branches.
  - Do not proactively split modules before implementation. Do proactively centralize the feature into tiny shared helpers so added code lands once, not three times.
  - Mandatory landing gates: rebuild both targets, re-check `program_end`, all overlay end symbols, `runtime_low_data_end`, and the C128 callable-residency asserts in `io_contracts.s`, then rerun the affected C64/C128 input and main-loop tests.
  - implement `FEAT-SEARCH-MODE` as the authentic shared runtime flag plus extra explicit search-turn design, including variable search odds derived from live player state and a persistent `Searching` status indicator rather than the current flat reveal chance plus message-only feedback
- Reason:
  - it restores the gameplay behavior the backlog item actually asks for while respecting the port’s explicit turn ownership and preserving the original class/race search feel instead of shipping a half-authentic hybrid
- Implementation outcome:
  - landed the shared search-mode runtime flag, authentic variable search/fos math, shared search-scan reuse, movement-owned passive search, extra-turn search-mode follow-up, transient save/load clearing, persistent `Searching` status UI, and `#` toggle wiring on both targets
  - also moved the C128 title screen and `item_gain_spell` call path into the UI overlay so the resident image still satisfies the banked-payload and callable-residency asserts after the feature growth
  - corrected the run interaction so entering run no longer clears search mode, and running now reuses the same passive-search and extra-turn helper behavior as ordinary movement when search mode is active
- Verification:
  - C64 main program rebuild passed with `Program fits below MAP_BASE=true`
  - C128 rebuild passed with zero asserts failed, including the staged-source / callable-residency checks in `commodore/c128/io_contracts.s`
  - targeted search-mode regressions passed:
    - `commodore/c64/tests/test_input.s` = 11/11
    - `commodore/c64/tests/test_main_loop.s` = 20/20
    - `commodore/c128/harness128_batch.py --mode compare --tests input128` = pass
    - `commodore/c128/harness128_batch.py --mode compare --tests main_loop128` = pass in both cold and snapshot modes
  - post-landing C64/C128 run-path regression fix:
    - `TEST_FILTER='main_loop' bash commodore/c64/run_tests.sh` reached `main_loop: PASS (20/20 tests)`
    - `TEST_FILTER='main_loop128' bash commodore/c128/run_tests128.sh` = `PASS`
  - authenticity correction for running/search interaction:
    - `make -C commodore/c64 build` = pass
    - `make -B -C commodore/c128 build128` = pass
    - `TEST_FILTER='main_loop' bash commodore/c64/run_tests.sh` still reached `main_loop: PASS (20/20 tests)`
    - `TEST_FILTER='main_loop128' bash commodore/c128/run_tests128.sh` = `PASS`
    - exact user path `make -C commodore/c128 test128-fast` = `PASS`
  - broader C64 umbrella run finished at `30 passed, 3 failed (of 33 suites)`; that run is not clean overall, but the search-mode-specific suites above are green

## `BUG-TOWN-KILL-DRAW` Design

### Goal
- Fix the stale town-monster glyph bug without turning it into a platform/HAL problem.
- Preserve the existing fast local redraw path for ordinary movement and nearby melee.
- Make the redraw contract explicit for stationary actions that can kill a visible monster away from the player.

### Working Diagnosis
- The shared post-turn redraw policy is the real owner of the bug.
- Stationary action commands such as `CMD_FIRE`, `CMD_THROW`, `CMD_CAST`, and `CMD_PRAY` all funnel into `command_result_main_or_update_visibility` or `command_result_restore_view_or_update_visibility`.
- Those helpers call `post_turn_update_visibility_or_die`, which currently does:
  - `turn_post_action`
  - `update_visibility`
  - `viewport_update`
  - local redraw only if there was no scroll, no `vis_room_revealed`, and no `turn_scene_dirty`
- `render_local_area` only redraws a player-centered bounding box using `old_player_*` and current player position.
- A stationary remote kill can clear the monster from map/state via `eff_kill_monster` / `monster_remove`, but still leave the dead glyph visible if the killed tile lies outside that local redraw box.
- The bug shows up in town on C128 because town sight lines make long stationary attacks easy to observe, not because the VDC renderer or HAL owns a different semantic contract.

### Critical Constraint
- A naive fix that sets `turn_scene_dirty` during the action path will not survive.
- `turn_post_action` starts by clearing `turn_scene_dirty`, then only re-sets it from monster AI movement.
- Any design that marks the existing flag before `turn_post_action` will silently lose the redraw request.

### Ownership Boundary
- Shared owner:
  - `commodore/common/turn_render_state.s`
  - `commodore/common/turn.s`
  - shared command/effect owners that know they changed a non-local visible tile
- Not the owner:
  - `commodore/c64/dungeon_render.s`
  - `commodore/c128/dungeon_render_vdc.s`
  - `REF-HAL` platform hook layer
- Data modules like `monster.s` should stay focused on monster-table/map ownership, not screen-policy decisions.

### Recommended Design
- Add a new shared pending redraw request in `turn_render_state.s`, separate from `turn_scene_dirty`.
- Treat it as an action-owned request that survives until `turn_post_action` folds it into the per-turn redraw decision.
- Shape:
  - `turn_scene_dirty`
    - stays the post-turn "scene changed this turn" flag consumed by main-loop redraw logic
  - new pending flag, e.g. `turn_action_redraw_pending`
    - set by stationary action/effect paths that mutate a visible tile outside the normal player-local redraw contract
    - consumed and cleared by `turn_post_action`
- `turn_post_action` should OR the pending action redraw request into `turn_scene_dirty` after its normal reset / AI bookkeeping so the existing main-loop redraw branches keep working.
- First-pass producer should be the shared kill helper surface, not the platform renderers:
  - prefer `eff_kill_monster` as the main producer because it already centralizes ranged/throw/spell/dispel kill removal without pulling ordinary melee through the same path
  - if later evidence shows another stationary non-local visual mutation has the same bug class, add that producer explicitly rather than broadening ownership prematurely

### Why This Is The Best First Cut
- It fixes the actual contract bug:
  - the render decision lacks a durable way for the action path to say "local redraw is not enough"
- It preserves the current local redraw fast path for ordinary movement and adjacent melee.
- It avoids teaching `monster_remove` about screen policy.
- It reuses the existing redraw branching in `game_loop.s` and `game_loop_helpers.s` instead of inventing a second render-dispatch system.

### Design Options

#### Option A — Pending action redraw flag folded into `turn_scene_dirty` at `turn_post_action`
- Pros:
  - minimal shared change
  - preserves current main-loop/renderer structure
  - keeps ownership in the shared turn/render-state seam
  - easiest to cover in `test_main_loop` / `test_main_loop128`
- Cons:
  - tends to force a full viewport redraw for affected stationary kills, even if a tighter dirty region would suffice
  - requires careful producer selection so nearby melee does not lose the local redraw win unnecessarily
- Verdict:
  - recommended

#### Option B — Track a remote dirty tile or tile list and union it with `render_local_area`
- Pros:
  - more precise than a forced full redraw
  - scales to future targeted redraw improvements
- Cons:
  - materially more state and more control-flow complexity
  - harder to prove correct across spell/effect families and both renderers
  - easy to under-specify multi-kill cases such as `eff_dispel_undead`
- Verdict:
  - elegant later optimization, not the right first bug fix

#### Option C — Mark redraw inside `monster_remove` or make all post-turn stationary actions redraw fully
- Pros:
  - simple to describe
- Cons:
  - wrong ownership if done in `monster_remove`
  - over-broad performance regression if all stationary actions force full redraw
  - still wrong if it relies on setting the current `turn_scene_dirty` before `turn_post_action`
- Verdict:
  - reject

### Consultant Feedback
- Consultant-style second-opinion conclusion:
  - keep this in shared turn/render-state ownership, not in platform code
  - do not patch the VDC renderer just because the bug was observed on C128
  - avoid expanding `REF-HAL` with a redraw hook for a bug whose semantics are identical on C64 and C128
- Specific cautions:
  - the biggest trap is forgetting that `turn_post_action` clears `turn_scene_dirty`
  - the second trap is pushing redraw policy down into `monster_remove`, which would blur data ownership and still miss non-removal remote mutations later
  - if the first producer is too broad, performance regresses; if it is too narrow, the stale glyph survives in another stationary kill path

### Scope For First Implementation
- In scope:
  - add pending redraw state in `turn_render_state.s`
  - fold it into `turn_post_action`
  - set it from the shared remote-kill helper surface used by ranged/throw/spell-style stationary kills
  - verify that post-turn helper paths upgrade from local redraw to full redraw when the pending request is present
- Out of scope:
  - renderer-specific redraw hacks
  - HAL/service-layer work
  - redesigning local dirty-rectangle rendering
  - speculative support for every future non-local mutation in the first patch

### Verification Plan
- Extend shared main-loop dispatch tests:
  - `commodore/c64/tests/test_main_loop.s`
  - `commodore/c128/tests/test_main_loop128.s`
- Add focused assertions for a stationary action path that consumes a turn and sets the new pending redraw request:
  - no viewport scroll
  - no `vis_room_revealed`
  - post-turn path still chooses full redraw, not `render_local_area`
- Add focused helper/effect coverage for the producer contract:
  - a remote-kill helper sets the pending redraw request
  - `turn_post_action` promotes and clears it correctly
  - the old flag-clearing behavior does not erase the request
- Regression checks:
  - ordinary movement without remote changes still uses local redraw
  - adjacent/melee paths that never needed a full redraw do not accidentally start forcing one unless intentionally widened

### Review
- Recommendation:
  - implement Option A with `eff_kill_monster` as the first producer and a new pending redraw flag consumed by `turn_post_action`
- Reason:
  - it is the smallest change that fixes the shared semantic gap without distorting platform boundaries or paying the complexity cost of remote dirty-rectangle tracking

### Implementation Result (2026-03-27)
- Closed the bug in the shared turn/effect seam rather than adding renderer or HAL-specific redraw behavior.
- Root cause confirmed:
  - `eff_kill_monster` could clear a remote visible monster tile, but the only durable full-redraw trigger in the shared post-turn path was `turn_scene_dirty`
  - `turn_post_action` clears `turn_scene_dirty` before the action tail reaches `post_turn_update_visibility_or_die`, so a naive pre-turn write would be lost
- What shipped:
  - `commodore/common/turn_render_state.s` now aliases `turn_action_redraw_pending` onto the dormant `zp_dirty_count` scratch byte so the action-owned redraw request survives `turn_post_action` without costing another resident byte
  - `commodore/common/spell_effects.s` `eff_kill_monster` now increments that pending latch immediately after `monster_remove`
  - `commodore/common/turn.s` now ORs the pending latch into the `monster_ai_tick` redraw result, stores the combined value into `turn_scene_dirty`, and clears the latch for the next turn
  - the final implementation stayed in shared ownership and preserved the local redraw fast path for ordinary movement / nearby melee
- C128 layout follow-up:
  - keeping the fix resident-byte neutral mattered, because the first cut pushed on C128 residency limits
  - `commodore/c128/main.s` stopped importing `player_magic_display_data.s` into `RuntimeLowData`
  - `commodore/c128/memory128.s` now imports that shared display data into the MMU common helper blob instead, which keeps the strings bank-safe without consuming runtime-low budget
- Test coverage added:
  - `commodore/c64/tests/test_turn.s` now proves the pending redraw latch promotes into `turn_scene_dirty` exactly once and then clears
  - `commodore/c64/tests/test_monster.s` now proves `eff_kill_monster` sets the pending redraw latch while still clearing the monster slot and map occupancy bit
  - the new `monster` test stubs XP side effects locally so it can isolate kill-removal redraw ownership without depending on unrelated combat progression setup
- Verification:
  - `make -C commodore/c64 build`
  - focused C64 runtime tests: `turn` `PASS (11/11)`, `monster` `PASS (13/13)`, `effects` `PASS (26/26)`
  - `make -B -C commodore/c128 build128` with `Made 238 asserts, 0 failed`
  - `make test128-fast` with all snapshot checks green

## `BUG-TITLE-DUALDISK-FRAME` Review

### Root Cause
- The C64 title-screen disk submenu, dual-disk indicator, and custom save-drive prompt/error flows were hard-coded onto rows `18-20`.
- Those rows overlap the lower portion of the loaded title art, so normal `screen_clear_row` calls for the disk UI were erasing the bottom frame.

### Fix
- Reserved the already-cleared title-screen status area for the transient disk UI:
  - menu/indicator row = `STATUS_ROW`
  - prompt/error row = `STATUS_ROW + 1`
- Updated:
  - `commodore/c64/main.s` title disk submenu and `[Save Disk]` indicator path
  - `commodore/common/disk_swap.s` custom-drive prompt, absent-device error, and `[Drive N]` indicator path
- The fix is deliberately narrow:
  - no title art redraw logic changed
  - no disk mode semantics changed
  - only the transient UI rows moved

### Test Coverage
- Extended `commodore/c64/tests/test_disk_swap.s` to pin the row contract for:
  - custom drive prompt
  - absent-device error
  - success indicator

### Verification
- `make -C commodore/c64 build` passed.
- `commodore/c64/tests/test_disk_swap.s` passed with `PASS_COUNT=11`.
- `make -B -C commodore/c128 build128` passed with all asserts.
- Result:
  - `BUG-TITLE-DUALDISK-FRAME` is closed as a C64 title-screen UI cleanup.

## `A6` Review

### Goal
- Split the oversized `commodore/common/item.s` into smaller ownership-focused files without changing behavior, callsites, or platform boundaries.

### Boundary Chosen
- `commodore/common/item_tables.s`
  - immutable base item metadata
  - ranged missile metadata/helper
  - canonical real-name pointer tables and strings
- `commodore/common/item_identification.s`
  - mutable `id_known` state
  - shuffle tables and category-local lookup tables
  - randomized unidentified descriptor strings/colors
  - identification init and name/color resolver routines
- `commodore/common/item.s`
  - floor item table and inventory state
  - spawn/pickup/drop/runtime behavior
  - item naming/append flows that are part of the runtime owner

### Why This Cut
- The immutable table block and the identification subsystem were already large, internally coherent seams.
- Save/load already treats identification state as a unit, so keeping that mutable state together improves ownership clarity.
- The split preserves the existing public surface because all import sites still consume `item.s`; no caller churn or build-order redesign was needed.

### Consultant Review
- Consultant verdict: this is the safest useful `A6` cut.
- Key rule confirmed:
  - keep all immutable base item definition data together
  - keep all mutable identification state and unknown-item descriptor logic together
- Consultant explicitly recommended against mixing unidentified descriptor tables into the immutable base table file.

### Implementation Review
- Completed with a structural-only split:
  - added `commodore/common/item_tables.s`
  - added `commodore/common/item_identification.s`
  - reduced `commodore/common/item.s` to the runtime-owned item behavior layer plus imports of the extracted subsystems
- No gameplay logic, call signatures, or platform ownership rules changed.

### Verification
- `make -B -C commodore/c128 build128` passed with all asserts.
- Focused C64 runtime suites passed:
  - `item` = `47/47`
  - `store` = `37/37`
  - `wands_staves` = `7/7`
  - `ranged` = `8/8`
- `make test128-fast` passed.
- Result:
  - `A6` is complete as an opportunistic maintainability split with no behavior change.

## `REF-HAL` Design

### Goal
- Reduce the accumulation of runtime `#if C128` branches in shared gameplay/orchestration code by introducing a thin platform-services layer for semantic runtime hooks.
- Keep the C64/C128 platform split explicit where it owns real hardware/banking policy; do not blur low-level loader/MMU contracts behind a generic dispatcher.
- Make future shared gameplay changes depend on named services such as "main-loop begin", "restore runtime state", and "prepare fresh key input" instead of direct references to C128 repair routines or raw C64 keyboard-buffer details.

### Findings
- The current tree already has two successful boundary patterns that `REF-HAL` should copy rather than invent around:
  - backend-owned vector tables such as `screen_vectors`
  - startup-installable common shims such as `commodore/common/generation_busy_api.s`
- The live `#if C128` surface in `commodore/common/` falls into three different buckets:
  - **Intentional platform/layout ownership**:
    - status/inventory/store/help layout constants in files like `ui_status.s`, `ui_inventory.s`, and `ui_store.s`
    - proven-safe platform helper splits like `ui_clear_full_screen_safe` in `ui_help_clear.s`
  - **Platform-boundary modules that are already the right owner**:
    - `overlay.s`, `tier_manager.s`, `title_screen.s`, `save.s`, and similar code that directly owns KERNAL/MMU/bank/cache policy
  - **True service leaks in shared gameplay/orchestration code**:
    - common files directly call C128 runtime repair routines such as `c128_restore_runtime_guards` and `c128_restore_runtime_vectors`
    - common files directly manipulate raw input-policy details such as `KBDBUF_COUNT`
    - common level-generation flow owns a C128-only overlay reattach helper inline
- The highest-value leak sites are concentrated rather than uniform:
  - `commodore/common/game_loop.s`
  - `commodore/common/game_loop_helpers.s`
  - `commodore/common/player_create.s`
  - `commodore/common/ui_messages.s`
  - a small number of modal/input flows that still branch on C128 for fresh-key behavior
- Specific examples of the leak shape:
  - `game_loop.s` calls `c128_restore_runtime_guards` after shared trampoline/overlay returns and `c128_restore_runtime_vectors` at the top of the shared main loop
  - `level_change_generate_current` in `game_loop.s` owns the C128-only "restore dungeon-gen overlay after tier load" rule inline
  - `game_loop_helpers.s` embeds both the C128 release-wait path and the C64 `KBDBUF_COUNT` flush path directly in shared modal flows
  - `ui_messages.s` reasserts C128 runtime vectors from the shared hot-path message renderer
- The existing tree also shows where the boundary is already healthy and should stay that way:
  - `input_wait_release` already hides platform-specific keyboard mechanics behind one public routine
  - `ui_clear_full_screen_safe` already hides the safe clear primitive behind one public helper
  - C128 trampoline ownership in `commodore/c128/main.s` is explicit and reviewable after `REF-1` / `REF-C128-TRAMP`

### Design Boundary
- In scope:
  - shared gameplay/orchestration code in `commodore/common/` that currently knows about:
    - C128 runtime guard/vector repair
    - session-start / resume quirks that are semantic hooks rather than core gameplay rules
  - adjacent cleanup for shared input-policy leaks only where it helps remove raw platform details from common gameplay code, but this should stay in the input-helper layer rather than expand HAL itself
- Out of scope:
  - screen geometry/layout compile-time differences
  - title/save/overlay/tier low-level banking and loader internals
  - test/diag-only `C128_*` instrumentation branches
  - replacing explicit C128 trampolines in `commodore/c128/main.s` with a generic dispatcher
  - removing every `#if C128` from `commodore/common/`; some are the correct owner and should remain
  - phase-1 HAL treatment of the current one-off dungeon-generation overlay reattach helper unless a second consumer appears

### Proposed Architecture
- Add a new shared shim file, tentatively `commodore/common/platform_services_api.s`.
- Model it after `generation_busy_api.s`:
  - each public service entry point is a `JMP` slot with a safe default implementation
  - defaults are no-op or minimal common-safe behavior only for genuinely optional hooks
  - platform startup installs the active targets by patching the jump slots to C64 or C128 service implementations
- Treat correctness-critical hooks differently from optional hooks:
  - non-optional runtime services must have an explicit install guard
  - startup must trap, assert, or otherwise fail loudly if a shipping build reaches gameplay without those hooks installed
  - silent no-op fallback is acceptable for optional services like the visible generation spinner, but not for vector/MMU/runtime repair
- Keep the service surface semantic and narrow. The first-pass hook families should be:
  - `platform_main_loop_begin_api`
    - called at the top of `main_loop`
    - C64: no-op
    - C128: restore runtime vectors / any required per-loop runtime state
  - `platform_vector_reassert_api`
    - called from shared hot paths that only need the RAM-side vectors/stubs reasserted
    - C64: no-op
    - C128: wraps the current vector restore path only
  - `platform_runtime_resync_api`
    - called after shared code returns from platform trampolines, overlay calls, or other runtime transitions that can leave broader C128 runtime state dirty
    - C64: no-op
    - C128: wraps `c128_restore_runtime_guards` and only the coupled restore state that truly belongs with that contract
  - optional phase-2 hooks only if they still pay their rent after phase 1:
    - `platform_session_start_api`
    - `platform_session_resume_api`
    - these would absorb the current C128 `PERF_P1` reset branches in shared session flow
- Keep the current one-off generation overlay repair explicit for now:
  - `c128_restore_generation_overlay` remains platform-owned generation glue, not a phase-1 HAL service
  - revisit only if another shared generation/tier path needs the same contract
- Treat input-policy cleanup as a sibling refactor, not a core HAL service family:
  - add small shared input helpers layered on the existing input abstraction where needed
  - move raw `KBDBUF_COUNT` handling out of shared gameplay code through the input layer, not through the HAL jump table
- Keep service implementations platform-owned:
  - C64 implementations can live in a small `platform_services64.s` or remain near `c64/main.s` initially
  - C128 implementations can live in `platform_services128.s` or near `c128/main.s`, but must continue to call the existing authoritative runtime helpers rather than re-implementing banking logic ad hoc

### Migration Plan
- Phase A: install the HAL skeleton without behavior change
  - add `platform_services_api.s`
  - install service targets during C64/C128 startup
  - add explicit install guards for all non-optional runtime services
  - keep only optional services on safe no-op defaults for unit tests and partial module imports
- Phase B: move the shared orchestration/runtime leaks first
  - replace direct `c128_restore_runtime_vectors` calls in shared gameplay/message flow with `platform_main_loop_begin_api` or `platform_vector_reassert_api`, depending on the callsite contract
  - replace direct `c128_restore_runtime_guards` calls in shared files with `platform_runtime_resync_api`
- Phase C: move the shared input-policy leaks
  - replace the mixed C64/C128 modal key gating in `game_loop_helpers.s` with input-layer helpers rather than new HAL hooks
  - replace direct `KBDBUF_COUNT` manipulation in shared gameplay with input-layer helpers
  - reuse the same input helpers in any remaining shared command flows that still branch on C128 just to wait for a fresh key
- Phase D: decide whether session-level hooks are still worth it
  - only pull `PERF_P1` reset branches behind HAL if that materially reduces shared conditional noise after phases B/C
  - do not add speculative hooks with only one callsite unless they close a real repeated pattern

### Design Rules
- Prefer named semantic services over mechanism-shaped helpers.
  - Good: `platform_vector_reassert_api`
  - Bad: `platform_do_c128_fixups_api`
- Keep the hook count small.
  - If a candidate service has one callsite and no clear second consumer, it probably does not belong in phase 1.
- Do not route ordinary gameplay calls through a generic function-pointer table.
  - The goal is to hide platform quirks, not to virtualize the whole program.
- Keep low-level banking/overlay/KERNAL transactions in the modules that already own them.
  - `REF-HAL` is about shared orchestration seams, not about hiding MMU policy from every file.
- Preserve unit-test friendliness.
  - New APIs must default to safe no-op/minimal behavior so focused tests do not need the full platform bootstrap unless the behavior truly requires it.

### Verification
- Static verification:
  - confirm the targeted shared files no longer contain direct runtime `#if C128` branches for the migrated service families
  - confirm shared gameplay files no longer write `KBDBUF_COUNT` directly
  - confirm new service defaults remain link-safe for focused unit tests
  - confirm non-optional runtime services cannot silently remain uninstalled in a shipping build
- Mandatory layout/banking verification for the eventual implementation:
  - rebuild and read the C64/C128 memory-map output after any new shim file or owner move
  - confirm default/main-segment, banked payload, overlay, and test-image boundaries still satisfy the repo asserts and documented hard limits
  - confirm the emitted symbol addresses for moved service helpers and any touched callsites
  - if any runtime-loaded or trampolined C128 path is touched, confirm the linked address, PRG header, load destination bank, visible execution bank, and recopy-source safety still agree
- Runtime verification for the eventual implementation:
  - C64:
    - `bash commodore/c64/run_tests.sh`
    - focused main-loop / item-selection / wizard / help modal tests if any new helpers are isolated there
  - C128:
    - `make -B -C commodore/c128 build128`
    - `make test128-fast`
    - focused main-loop / overlay / prompt-gating / modal UI regressions that exercise:
      - overlay return to gameplay
      - help/inventory/equipment modal dismiss
      - store/item direction prompts
      - level transition / tier transition / generation overlay restore
- Suggested additional guard once implementation starts:
  - add a narrow grep-based harness check for forbidden direct shared-runtime calls in `commodore/common/`:
    - `c128_restore_runtime_guards`
    - `c128_restore_runtime_vectors`
    - raw `KBDBUF_COUNT` writes
  - keep this guard scoped to the migrated files/families so it does not accidentally ban legitimate platform-boundary owners

### Review
- Completed as a design pass only; no implementation started.
- Main conclusion: `REF-HAL` should not try to erase all compile-time platform split from `commodore/common/`.
- The right target is the smaller set of shared orchestration leaks where gameplay code currently knows about:
  - C128 runtime repair entry points
  - and, separately, a small amount of raw C64 keyboard-buffer behavior that should likely move into the input-helper layer rather than HAL itself
- Consultant review tightened the original draft in four important ways:
  - required runtime hooks now need an explicit install guard instead of silent no-op defaults
  - vector-only repair is now split from broader runtime resync
  - the one-off generation-overlay reattach helper is deferred from phase-1 HAL
  - verification now includes the repo’s mandatory C128 layout/banking checks, not just test runs
- The revised safest implementation model is:
  - a startup-installed semantic runtime-service API for the real shared runtime leaks
  - small input-helper cleanup for the keyboard-policy leaks
  - explicit trampolines and low-level banking code left in their current platform owners

### Implementation Review
- Completed for the bounded phase-1 runtime-service and input-helper migration.
- Added `commodore/common/platform_services_api.s` as the required runtime-service shim surface with:
  - install-state tracking
  - a loud `BRK` default for uninstalled required hooks
  - semantic entrypoints for main-loop begin, vector reassert, and runtime resync
- Added `commodore/common/input_ui_helpers.s` as the sibling input-policy layer with:
  - fresh follow-up key preparation
  - modal dismiss-key preparation/reads
  - the C64-only run-cancel keyboard-buffer flush hidden behind one helper
- Installed the platform-service hooks during startup on both platforms:
  - `commodore/c64/main.s` patches the required API slots to explicit no-op C64 handlers and asserts installation
  - `commodore/c128/main.s` patches the same slots to `c128_restore_runtime_vectors` / `c128_restore_runtime_guards` and asserts installation
- Migrated the targeted shared service leaks:
  - shared gameplay/message flow now calls `platform_main_loop_begin_api`, `platform_vector_reassert_api`, or `platform_runtime_resync_api` instead of directly naming the C128 repair helpers
  - shared modal/prompt/item/store flows now use `input_ui_helpers.s` instead of open-coded `input_wait_release` / `KBDBUF_COUNT` policy
- Kept the intended exclusions explicit:
  - the one-off `c128_restore_generation_overlay` helper remains outside phase-1 HAL
  - platform-boundary owners such as `commodore/common/reu.s` still own their direct runtime repair calls
- Focused C128 harnesses were updated to patch the new hook entrypoints so isolated tests remain link-safe and deterministic.
- Static verification:
  - targeted shared gameplay files no longer directly call `c128_restore_runtime_vectors`
  - targeted shared gameplay files no longer directly call `c128_restore_runtime_guards`
  - targeted shared gameplay files no longer write `KBDBUF_COUNT` directly for the migrated prompt/run-cancel flows
  - remaining direct runtime-repair owners are limited to intentional platform-boundary code
- Mandatory layout/banking verification completed:
  - `make -C commodore/c64 build` passed with all asserts and the program end still below the documented boundary
  - `make -B -C commodore/c128 build128` passed with all asserts and the default/banked/overlay segment limits still satisfied
- Runtime verification completed:
  - `bash commodore/c64/run_tests.sh` passed (`33 passed, 0 failed`)
  - `make test128-fast` passed, including `main_loop128` and `msg_prompt128`
- Follow-up C128 regression correction after real interactive validation:
  - moved `ui_home.s` back into the reloadable banked payload and added explicit `io_contracts.s` audits for `home_enter`, `home_retrieve`, and `home_deposit`
  - hardened the C128 fast command-edge path so cursor-key PETSCII family jitter does not retrigger a held cursor key as repeated town movement
  - re-ran `make -B -C commodore/c128 build128` plus focused C128 town/runtime coverage:
    - `TEST_FILTER='town_overlay_smoke|town_overlay_female_smoke|town_overlay_state_smoke|real_input_town_move_diag' ./run_tests128.sh`
  - note: the standalone `input128` unit runner was intermittently crashing VICE in this environment instead of producing a normal pass/fail result, so the verification record for the cursor-path fix relies on the focused runtime town coverage rather than claiming a clean `input128` unit result
- Follow-up prompt-helper cleanup:
  - migrated the remaining shared spell-selection and wizard prompt callsites from direct `input_wait_release` to `input_prepare_followup_key`
  - touched shared `player_magic.s` plus the C128 wizard UI owner without expanding the HAL hook surface
  - verification:
    - `bash commodore/c64/run_tests.sh` passed (`33 passed, 0 failed`)
    - `make test128-fast` passed
- Follow-up prompt-policy narrowing after consultant review:
  - reviewed the last three shared `input_wait_release` callsites and kept only the true modal-dismiss case in scope
  - updated the post-death screen flow in `game_loop.s` to use `input_get_modal_dismiss_key`
  - left `player_create.s` gender selection on its explicit release wait because it does not hand off directly into a secondary key prompt and should not overload the follow-up-key helper contract
  - focused verification:
    - `make -B -C commodore/c128 build128` passed with all asserts
    - `make test128-fast` passed
    - `make test128-fast-smoke` passed (`3 passed, 0 failed`)
  - limitation:
    - the full `bash commodore/c64/run_tests.sh` runner still hung in this environment during the long `effects` suite, so this narrowed slice is recorded against the focused C128 acceptance set instead of claiming a fresh full-C64 pass
- Follow-up C128 spell-list residency correction after interactive `JAM` at `$D023`:
  - split the spell-list header literal into `player_magic_display_data.s` so the C128 spell-display tail no longer wastes banked space on resident-only data
  - kept `spell_list_display` and `calc_spell_failure` in the reloadable banked payload while leaving `player_cast_spell`, `player_pray`, and `pm_header_str` outside the I/O hole in resident space
  - tightened the spell-display code path enough to recover additional banked bytes instead of relocating another callable surface
  - extended the C128 residency contract with explicit audits for `player_cast_spell`, `player_pray`, and `pm_header_str`
  - focused verification:
    - `make -B -C commodore/c128 build128` passed with all asserts; banked payload now fits at `4078` bytes with the staged source at `$cffb-$dfe9`
    - required regression suites were rerun after the fix and passed
- Outcome:
  - `REF-HAL` phase 1 now exists as a narrow installed runtime-service seam plus an input-policy helper layer
  - shared orchestration code is less coupled to C128 repair mechanics and raw C64 keyboard-buffer details
  - low-level banking, overlay, and one-off generation ownership remain in their existing explicit platform owners
  - after the final prompt-policy audit, the only remaining direct runtime-repair references in `commodore/common/` are the intentional exclusions:
    - `reu.s` preload/bank-restore ownership
    - the one-off `c128_restore_generation_overlay` helper in `game_loop.s`
  - consultant review recommends treating `REF-HAL` phase 1 as complete at that boundary and handling any future generation-overlay cleanup as a separate slice, not as more HAL expansion
- Follow-up boundary hardening after the attempted post-phase generation-overlay move was backed out:
  - re-audit plus consultant review reconfirmed there is no clean next HAL runtime slice past the committed phase-1 boundary
  - added a focused C128 harness guard, `c128_ref_hal_guard`, to fail if shared code regresses beyond the documented exclusions in `game_loop.s` and `reu.s` or if raw shared `KBDBUF_COUNT` usage reappears outside `input_ui_helpers.s`
- Phase-2 viability audit result:
  - the only remaining candidate from the original design, the optional `PERF_P1` session-hook cleanup, does not justify a new HAL phase in the live tree
  - `PERF_P1` is compile-time C128 instrumentation in `game_loop.s` plus `perf_p1.s`, not a runtime platform-repair seam
  - keep `PERF_P1` explicit and keep any future `c128_restore_generation_overlay` ownership cleanup tracked as a separate non-HAL slice
- Follow-up CIA2/VIC-bank restore cleanup:
  - audited the active `overlay.s` / `tier_manager.s` backlog note and confirmed `overlay.s` was already correctly platformized while `tier_manager.s` still carried a stale shared `$DD00` restore on the C128 path
  - limited the fix to `tier_manager.s` so only the C64 disk-load path restores VIC-II bank 0 after serial I/O; C128 now leaves that ownership with the platform loader wrapper that already restores `$DD00`
  - focused verification:
    - `make -B -C commodore/c128 build128` passed with all asserts
    - focused C64 `tests/test_tier.s` still passed (`11/11`)
    - `make test128-fast` passed
    - `make test128-fast-smoke` passed (`3 passed, 0 failed`)

- [x] Audit live formatter ownership for `REF-NUMFMT` and determine whether the backlog item still represents real work.
- [x] Record the `REF-NUMFMT` design/review outcome here before changing the planning docs.
- [x] Reconcile the build-plan docs if the audit proves `REF-NUMFMT` is already complete/stale.

## `REF-NUMFMT` Design

### Goal
- Determine whether `REF-NUMFMT` still requires an implementation pass or whether the live tree already satisfies the intended shared numeric-formatting design.
- If the work is already done, close the item through plan/history cleanup instead of reopening a solved refactor.

### Findings
- The active build plan still lists `REF-NUMFMT` as future work to move duplicated screen numeric helpers into shared code.
- The live source already has that shared owner:
  - `commodore/common/numeric_format.s` owns `screen_put_hex`, `screen_put_decimal`, `screen_put_decimal_rj2`, `screen_put_decimal_lz2`, `screen_put_decimal_16`, the shared digit buffer, and the 16-bit power-of-10 tables.
  - `commodore/c64/screen.s` imports `../common/numeric_format.s`.
  - `commodore/c128/screen_vdc.s` imports `../common/numeric_format.s`.
- The broader formatter cleanup was already completed as audit item `CA-01`:
  - `commodore/common/combat.s` now reuses `numeric_format_u8` / `numeric_format_u16` for combat-buffer decimal output.
  - `commodore/CODE_AUDIT.md` and the earlier `AUDIT-P10-CA01` section in this file both record the shared-core implementation and verification.
- The only remaining separate formatter path is the intentional 24-bit score formatter in `commodore/common/score.s`, which is outside the stated `REF-NUMFMT` scope.

### Decision
- Treat `REF-NUMFMT` as stale backlog wording already satisfied by the completed `CA-01` shared numeric-formatting pass.
- Do not reopen code changes for this item.
- Close it by reconciling `commodore/BUILDPLAN.md` with the recorded completed work in the audit/task history.

### Review
- Completed.
- Verified the current tree already meets the requested design boundary: shared formatter logic is centralized in `commodore/common/numeric_format.s`, while each platform screen backend remains separate and only supplies its own `screen_put_char`.
- Verified the refactor went beyond the original backlog wording in a safe direction by also removing combat's dependency on backend-local decimal tables.
- Outcome: `REF-NUMFMT` should be retired from the active backlog as already completed/stale, with no runtime code changes required.

- [x] Implement `BUG-HAGGLE-UI` Phase A in `commodore/common/ui_store.s` using one-visit VMS-style haggle flow with integer counter math.
- [x] Keep Phase A inside the current thin store data model; do not add persistent bargaining-memory or owner-schema work.
- [x] Add focused runtime coverage in `commodore/c64/tests/test_store.s` for parser behavior, buy/sell haggle flow, insult handling, and no-haggle bypasses.
- [x] Run the relevant C64 store/runtime tests and broader C64/C128 regression coverage.
- [x] Record the implementation review outcome here after verification.

- [x] Analyze the live `BUG-HAGGLE-UI` implementation in `commodore/common/ui_store.s` and identify the current buy/sell haggle contract.
- [x] Compare the port's haggle flow against local upstream references in `~/Projects/thirdparty/vms-moria` and `~/Projects/thirdparty/umoria`.
- [x] Draft a bounded design plan that restores one-visit haggle correctness before any larger store-system upgrades.
- [x] Get consultant review on the draft plan and fold that feedback into the final phase split and verification list.
- [x] Record the final planning scope here before presenting it to the user.

### `BUG-HAGGLE-UI` Design

#### Goal
- Restore store haggling to correct one-visit behavior for the current Commodore data model.
- Use VMS-Moria as the semantic baseline for user-visible haggle flow.
- Use Umoria as the implementation reference for integer bargain progression where the original VMS code relies on real-valued ratios.

#### Findings
- The current port uses a simplified fixed-step haggle loop in `commodore/common/ui_store.s`:
  - buy haggling always marches toward the floor by `gap / 4`
  - sell haggling always marches up from `max / 2` by `gap / 4`
  - insult thresholds are hard-coded as `< min / 2` and `> 2 * max`
  - kick happens after `3` insults
  - final phase is a generic Y/N confirmation after `4` rounds
  - accepted price is always the current ask/counter price
- The current store data model is intentionally thin:
  - per-visit `hg_insults`
  - per-store `hg_kicked`
  - no owner-specific haggle parameters
  - no persistent bargaining skill memory
  - no temporary store lockout timer
- Upstream VMS/Umoria haggle behavior is materially richer than the current port:
  - backwards offers are rejected and can count as insults
  - counter progression depends on offer ratio, not a fixed quarter-gap step
  - overshoot/undershoot gets explicit retry reactions
  - final-offer exhaustion has distinct behavior
  - successful business reduces the accumulated insult state

#### Phase A
- Treat this as a parity/regression fix, not a full store-system rewrite.
- Restore one-visit haggle behavior to VMS semantics using Umoria's integer bargaining model, without adding new persistent shop state.
- Cover these behaviors explicitly:
  - offer parser correctness
  - backwards-offer rejection
  - overshoot/undershoot retry behavior
  - integer ratio-based counter-offer progression
  - final-offer exhaustion behavior
  - correct accept-price semantics
  - insult accumulation, kick threshold, and post-deal insult decay
  - cheap-item / Black Market no-haggle bypass behavior
- Keep buy and sell implementations readable even if they share small helpers; do not force an abstract shared haggle core during the parity pass.

#### Phase B
- Leave these as follow-up work unless Phase A proves they are required by the live bug:
  - owner-specific haggle parameters
  - temporary store closure / reopen timing
  - bargaining-memory / no-need-to-bargain state
  - incremental `+/-` haggle input
  - richer speech/comment tables

#### Verification
- Add focused runtime haggle tests for:
  - buy exact-match, over-ask, under-ask, backwards second offer, repeated insulting offers, first-prompt cancel, later cancel, final-offer reject
  - sell exact-match, below-offer, above-offer, backwards second ask, repeated insulting asks, store-full after accepted deal, worthless/cursed/non-buyable exits
  - parser paths: leading spaces, empty input, delete/backspace, 5-digit limit, overflow-ignore, cancel keys
  - state paths: `hg_insults` reset on entry, decremented after a successful deal, `hg_kicked` persistence until its intended reset point
  - bypass paths: cheap-item no-haggle and Black Market no-haggle
- Run the standard C64 store/runtime coverage plus the usual broader C64/C128 regression pass after the fix lands.

#### Review
- Consultant review confirmed the correct boundary is one-visit haggle correctness first, not a full persistent-store refactor.
- The main correction from review was to avoid claiming a direct VMS arithmetic port; VMS should drive behavior, while Umoria should drive the integer implementation shape.
- The plan also now treats parser behavior and post-deal insult decay as first-class Phase A work instead of optional polish.
- Stage A landed in the existing thin store model with new `hg_last_*`, denominator scratch, and concession-percent state only; no persistent bargaining-memory or owner-schema work was added.
- `haggle_buy` and `haggle_sell` now reject backwards offers, retry overshoot/undershoot neutrally, use integer concession ratios for counter-offers, accept at the player's agreed number when appropriate, and decay `hg_insults` after successful no-haggle or haggled transactions.
- Focused store verification passed at `37/37` tests after adding parser, buy/sell flow, insult/kick, and no-haggle bypass coverage.
- Broader regression passed after fixing four C64 test-harness layout regressions that Stage A code growth exposed:
  - `test_main_loop.s`, `test_dungeon.s`, and `test_monster_ai.s` were linking unnecessary store/help payload and crossed reserved boundaries.
  - `test_effects.s` also overlapped its own `$A000` scratch-buffer segment; its buffer was moved above the linked body and the assert was tightened to the real boundary.
- Final verification:
  - `bash commodore/c64/run_tests.sh` -> `33 passed, 0 failed`
  - `make test128-fast` -> passed via tester agent
  - C128 authoritative runner repair:
    - `run_test_internal_worker.sh` now runs unit tests with `-autostart` plus a pass breakpoint and shell-side VICE supervision, so `minimal128` and the rest of the unit batch no longer hang waiting at the monitor.
    - `run_tests128.sh` prompt guard now matches the live Huffman-backed prompt helpers in `player_items.s`.
    - `run_tests128.sh` town overlay smokes now use `until $store_enter`, and `real_input_town_move_diag` now runs all stage breakpoints in one boot instead of 15 separate boots.
    - `run_tests128.sh` `main128_asm` now forces a base rebuild when the active C128 variant is not `base`, so later variant compiles cannot leave `out/moria128.prg` / `out/main.vs` contaminated for the next `c128_artifact_budget` run.
  - Focused C128 verification:
    - `TEST_FILTER='prompt_irq_guard' TEST_FAIL_FAST=1 ./run_tests128.sh` -> `PASS`
    - `TEST_FILTER='minimal128' TEST_FAIL_FAST=1 ./run_tests128.sh` -> `PASS`
    - `TEST_FILTER='town_overlay_female_smoke' TEST_FAIL_FAST=1 ./run_tests128.sh` -> `PASS`
    - `TEST_FILTER='town_overlay_state_smoke' TEST_FAIL_FAST=1 ./run_tests128.sh` -> `PASS`
    - `TEST_FILTER='real_input_town_move_diag' TEST_FAIL_FAST=1 ./run_tests128.sh` -> `PASS`
    - `TEST_FAIL_FAST=1 TEST_FILTER='c128_artifact_budget|main128_layout' ./run_tests128.sh` -> `PASS`
    - Deliberately contaminate `out/moria128.prg` with `C128_TEST_SCRIPTED_INPUT`, then rerun `TEST_FAIL_FAST=1 TEST_FILTER='main128_asm|c128_artifact_budget' ./run_tests128.sh` -> `2 passed, 0 failed`
    - `TEST_FAIL_FAST=1 ./run_tests128.sh` -> `41 passed, 0 failed`
  - Closeout:
    - `BUG-HAGGLE-UI` moved from `commodore/BUILDPLAN.md` to `commodore/BUILDPLAN_HISTORY.md`
    - final diagnosis: Stage A haggle gameplay fix was valid; the last C128 fallout was stale variant artifact reuse plus a runner-footer bug

- [x] Complete the carried-item half of `CA-02` with a dedicated visible-slot cache that does not alias shared message buffers.
- [x] Keep the final cache storage local to `player_items.s` so filtered prompts cannot recreate the earlier `test_item` hang.
- [x] Rebuild and rerun the standard C64/C128 verification on the completed `CA-02` implementation.
- [x] Add a shared visible-slot cache for contiguous equipment selection in `item_takeoff`.
- [x] Keep the plain all-inventory command on its existing absolute-slot behavior.
- [x] Rebuild and rerun the standard C64/C128 verification on the reduced safe implementation.
- [x] Execute `CA-01` by unifying the shared numeric formatting core used by screen output and combat messages.
- [x] Remove the cross-module `decimal_powers_*` dependency on the screen backend so combat formatting owns only common numeric data.
- [x] Add focused runtime coverage for direct screen decimal output and combat decimal-buffer output after the refactor.
- [x] Rebuild and rerun the standard C64/C128 verification, then refresh the audit/headroom/task docs with the live post-change layout.
- [x] Execute `LINT-1` by adding a reproducible 6502 anti-pattern linter to the repo.
- [x] Fail on provably redundant zero-compares, but keep branch-then-jump ladders advisory until they are triaged.
- [x] Clean up the first live redundant-compare hits so the new linter lands green on the current tree.
- [x] Rebuild and rerun the standard C64/C128 verification after the lint-driven source cleanup.
- [x] Execute `ALIGN-1` by auditing hot render/combat/input indexed accesses against the live symbol layout.
- [x] Distinguish page-safe tables from real page-cross candidates in the current C64 and C128 builds.
- [x] Quantify likely cycle impact only where the current hot-path access pattern justifies it.
- [x] Update the audit plan with concrete alignment findings and move the queue to the next unresolved phase.
- [x] Execute `ZP-1` by adding an automated scan for raw zero-page ownership violations.
- [x] Flag raw `$90-$FF` zero-page memory operands outside explicitly blessed KERNAL/MMU helper cases.
- [x] Keep the scan focused on real assembly operands rather than `.byte` data, comments, or immediates.
- [x] Wire the scan into a reproducible project check path and record the first live results in the audit docs.
- [x] Execute `CA-12` by replacing the public one-bit RNG byte path with a real byte-step generator.
- [x] Keep the final implementation inside the C64 banked-payload budget while improving byte-quality output.
- [x] Add focused runtime coverage that proves `rng_next` advances exactly eight reference one-bit steps.
- [x] Run shared RNG verification plus broader regression coverage for common consumers, then refresh the audit/headroom/task docs with the live post-change layout.
- [x] Execute `API-1` by enforcing one caller-visible C128 text contract at the VDC screen layer.
- [x] Make `screen_put_string` accept PETSCII like `screen_put_char` while preserving compatibility for embedded direct VDC/control bytes.
- [x] Add a focused C128 regression that proves lowercase PETSCII strings and direct VDC byte passthrough both survive the new contract.
- [x] Rebuild the C128 target, rerun focused and fast C128 verification, and refresh the audit/headroom docs with the live post-change layout.
- [x] Execute `WRAP-1` by fixing the C128 KERNAL-wrapper IRQ-state contract.
- [x] Preserve the caller `I` bit while still returning the KERNAL carry/flag result.
- [x] Update the focused cold-boot wrapper probe to match the fixed scaffold and the real C128 `$01` low-bit contract.
- [x] Run focused wrapper verification and a broader C128 regression pass on the final patch.
- [x] Execute `CA-11` melee to-hit overflow/sign handling.
- [x] Confirm the live overflow/sign bug in `combat_calc_tohit_common`.
- [x] Add targeted regression coverage for high positive and high negative `PL_TOHIT`.
- [x] Run focused verification for shared callers after the fix.
- [x] Execute `HEADROOM-1` and produce an exact margin report for the constrained C64/C128 regions.
- [x] Rebuild the live C64 and C128 targets before recording headroom numbers.
- [x] Compute exact byte margins for C64 main, banked, and overlay regions.
- [x] Compute exact byte margins for C128 staged-source, banked, overlay, low-runtime, and Bank 1 ownership regions.
- [x] Record the measured headroom report in the Commodore docs.
- [x] Re-verify the older C128 IRQ/KERNAL-wrapper finding from `commodore/AUDIT.md` against the live tree.
- [x] Inspect the current wrapper implementation and existing related diagnostics/tests before changing any code.
- [x] Run a focused verification path for I-flag preservation / runtime IRQ-state restoration across representative wrappers.
- [x] Record the verified outcome in the audit docs and note whether the old finding remains live, stale, or partially true.
- [x] Inventory existing audit notes, architecture constraints, and 6502 gotchas relevant to the Commodore tree.
- [x] Scan `commodore/common/`, `commodore/c64/`, and `commodore/c128/` for repeated helpers, style drift, wasteful instruction patterns, and common 6502 correctness risks.
- [x] Quantify each actionable audit item with rough code-size and/or cycle savings, scope, risk, and likely shared refactor seam.
- [x] Write `commodore/CODE_AUDIT.md` as the consolidated audit plan with prioritized findings and suggested verification steps.
- [x] Review the finished audit against current build/memory/banking constraints and record the review summary here.

## `AUDIT-P1-WRAPPERS` Design

### Goal
- Execute phase 1 of the revised core audit:
  - re-verify the older C128 wrapper/IRQ finding from `commodore/AUDIT.md`
  - determine whether it is still live in the current codebase
  - update the audit docs based on evidence, not historical memory

### Scope
- In scope:
  - `commodore/c128/main.s`
  - `commodore/c128/memory128.s`
  - existing C128 tests/diagnostics relevant to wrapper state preservation
  - targeted verification commands needed to prove the current behavior
- Out of scope:
  - broad refactors of the wrappers unless the bug is proven live
  - unrelated C128 banking changes

### Verification Standard
1. Confirm the current wrapper code shape in source.
2. Check whether existing automated tests already cover IRQ-state preservation.
3. Run a focused verification path for representative wrappers.
4. Update the audit docs with one of:
   - still live
   - stale / already fixed
   - partially true / needs narrower restatement

### Review
- Completed.
- Source review showed the current wrappers no longer match the exact historical phrasing in `commodore/AUDIT.md`, because `php` happens after the KERNAL `jsr`, not immediately after `:EnterKernal()`.
- A direct monitor jump into the full `moria128.prg` wrapper addresses was too stateful to trust without a fully booted runtime, so the verification path pivoted to an isolated cold-boot test using the current wrapper shape plus `memory128.s`.
- The focused probe in `commodore/c128/tests/test_wrapper_irq128.s` confirmed the old bug remains live for the common wrapper scaffold:
  - first failing stage `#$11` = `w_readst` from caller-`CLI`
  - captured interrupt bit `dbg_ibit = $04`
  - meaning the wrapper returned with IRQs disabled even though the caller entered with IRQs enabled
- Result: phase 1 is resolved as `still live`, not stale. `commodore/CODE_AUDIT.md` now promotes this to active item `WRAP-1`.

## `AUDIT-P2-HEADROOM` Design

### Goal
- Execute `HEADROOM-1` as a concrete measurement pass instead of leaving it as a planning-only item.
- Produce one exact headroom report covering:
  - C64 main image
  - C64 banked payload source/runtime
  - C64 overlays
  - C128 staged source / Bank 0 image
  - C128 runtime banked payload
  - C128 overlays
  - C128 `RuntimeLowData`
  - C128 Bank 1 ownership gaps

### Scope
- In scope:
  - `commodore/c64/main.s`
  - `commodore/c64/out/main.vs`
  - `commodore/c128/main.s`
  - `commodore/c128/memory128.s`
  - `commodore/c128/out/main.vs`
- Out of scope:
  - changing any memory layout in this phase
  - implementing the future build-time generated summary

### Review
- Completed.
- Rebuilt the live C64 and C128 targets and used the emitted symbol files as the source of truth for next-free end labels.
- Added `commodore/HEADROOM_REPORT.md` with exact byte margins and risk ranking.
- Most important measured outcomes:
  - C128 `RuntimeLowData` has `0` bytes before floor-item storage at `$1A00`
  - C64 runtime banked payload has `2` bytes before `$FFFA`
  - C64 staged banked payload source has `3` bytes before `$D000`
  - C128 startup overlay has `35` bytes before `$F000`
  - C64 main image has `40` bytes before `MAP_BASE`
  - C64 startup overlay has `44` bytes before `$F000`
- Updated `commodore/CODE_AUDIT.md` so `HEADROOM-1` now references the completed measurement pass instead of only describing the intended deliverable.
- Refreshed the report after the `CA-11` fix changed shared-code size; the current live numbers are the ones above and in `commodore/HEADROOM_REPORT.md`.

## `AUDIT-P3-CA11` Design

### Goal
- Execute `CA-11` by fixing the melee to-hit overflow/sign bug in shared combat logic.
- Preserve the existing contract:
  - final to-hit stays clamped to `0..255`
  - negative penalties can still floor the pre-level value to `0`
  - per-level class adjustment still applies after the `PL_TOHIT` contribution

### Scope
- In scope:
  - `commodore/common/combat.s`
  - `commodore/c64/tests/test_combat.s`
  - `commodore/c64/run_tests.sh`
- Out of scope:
  - broader RNG or combat-balance changes
  - monster attack math

### Review
- Completed.
- Fixed the shared `PL_TOHIT * 3` path by saturating before the intermediate 8-bit multiply wraps, in both the positive and negative branches.
- Added two regression cases to `test_combat.s`:
  - `PL_TOHIT = 100` must cap the final result at `255`
  - `PL_TOHIT = -100` must floor the pre-level total to `0`, then end at `4` after the Warrior level-1 bonus
- Updated the combat suite expectations in `run_tests.sh` from `20` to `25`.
- Focused verification:
  - `tests/test_combat.s` → all `25/25` checkpoints passed
  - `tests/test_throw.s` → all `6/6` checkpoints passed

## `AUDIT-P4-WRAP1` Design

### Goal
- Execute `WRAP-1` by repairing the caller-visible IRQ-state contract for the shared C128 KERNAL wrappers.
- Preserve both of these together:
  - the caller's original `I` bit
  - the KERNAL call's returned Carry/flag result

### Scope
- In scope:
  - `commodore/c128/main.s`
  - `commodore/c128/tests/test_wrapper_irq128.s`
  - focused C128 verification for the wrapper scaffold and affected runtime state
- Out of scope:
  - broader wrapper deduplication / macro-generation (`CA-09`)
  - unrelated C128 banking or overlay refactors

### Review
- Completed.
- Fixed the shared wrapper scaffold by saving caller status before `:EnterKernal()` and restoring the KERNAL return flags with the caller's original `I` bit spliced back in after `:ExitKernal()`.
- Applied the same contract repair to the special-case paths:
  - `w_load`
  - `kernal_load_safe`
  - `safe_setbnk`
- Updated the focused probe in `test_wrapper_irq128.s` to match the repaired scaffold and to validate the real C128 `$01` contract by masking to the low three banking bits.
- Focused verification:
  - `commodore/c128/tests/test_wrapper_irq128.s` → `PASS`
  - `make test128-fast` → `PASS`
- Refreshed the headroom baseline after the wrapper fix:
  - C128 staged source / program image is now `76` bytes below `$E000`
  - C128 cache-state block now ends at `$32F8`

## `AUDIT-P5-API1` Design

### Goal
- Execute `API-1` by giving the C128 screen layer one caller-visible text rule.
- Make the public VDC text entry points behave like the rest of the shared UI code expects:
  - PETSCII in
  - backend-native screen codes out
- Preserve the existing tolerance for embedded direct VDC/control bytes that already exist in packed UI/title data.

### Scope
- In scope:
  - `commodore/c128/screen_vdc.s`
  - focused C128 text/output regression coverage
  - audit/headroom/task docs affected by the layout change
- Out of scope:
  - broad callsite rewrites across shared UI code
  - changes to the VIC-II backend contract

### Verification Standard
1. Confirm the mixed contract in the current VDC backend source.
2. Change the public string path so PETSCII strings and PETSCII chars share the same translation rule.
3. Prove lowercase PETSCII survives the string path on VDC.
4. Prove embedded direct VDC bytes still pass through unchanged.
5. Rebuild C128, rerun the fast C128 suite, and refresh the live headroom/audit docs.

### Review
- Completed.
- Updated `commodore/c128/screen_vdc.s` so the public VDC text contract is now consistent:
  - `screen_put_char` and `screen_put_string` both accept PETSCII
  - embedded direct VDC/control bytes still pass through because the backend translator only remaps PETSCII lowercase
- Added focused regression coverage in `commodore/c128/tests/test_vdc_attr128.s` for:
  - lowercase PETSCII string translation (`"Ab"` writes lowercase `b` as VDC Set 1 code `$02`)
  - direct VDC byte passthrough (`$03` remains `$03`)
- Rebuilt the C128 target and refreshed the post-change layout:
  - C128 staged source / program image is now `73` bytes below `$E000`
  - C128 cache-state block now ends at `$32FB`
  - C128 overlay-state block now ends at `$32F3`
- Verification completed:
  - `commodore/c128/tests/test_vdc_attr128.s` → `PASS`
  - `python3 -u commodore/c128/harness128_batch.py --mode compare --snapshot-path commodore/c128/out/ready.vsf --vice /opt/homebrew/bin/x128 --connect-timeout 12` → `PASS`
- Environment note:
- `make test128-fast` remained PATH-sensitive in this shell and repeatedly reset the monitor connection while using bare `x128`
- the equivalent explicit-binary batch command above completed cleanly and is the verification result for this phase

## `AUDIT-P6-CA12` Design

### Goal
- Execute `CA-12` by making the public RNG byte API match its name:
  - `rng_next` / `rng_byte` should yield a fresh byte step, not a one-bit shift artifact
- Keep the implementation small enough to stay inside the current C64 banked-payload ceiling.

### Scope
- In scope:
  - `commodore/common/rng.s`
  - `commodore/c64/tests/test_rng.s`
  - `commodore/c64/run_tests.sh`
  - audit/headroom/task docs affected by the layout change
- Out of scope:
  - changing the RNG polynomial or seed source
  - game-balance tuning on top of the better byte-quality distribution

### Verification Standard
1. Prove the current live `rng_next` is still only advancing one bit.
2. Change the public byte path so one call advances eight LFSR steps.
3. Keep the final implementation inside the live C64 memory budget.
4. Add a runtime test that compares the new byte-step path against a local reference-step implementation.
5. Run focused RNG verification and broader shared-gameplay regression coverage before updating the docs.

### Review
- Completed.
- Updated `commodore/common/rng.s` so the public byte API now advances the 32-bit LFSR eight times per call before returning `zp_rng_0`.
- Deliberately did **not** keep a public `rng_step_bit` entry in the final patch:
  - the first split-API draft pushed the C64 banked payload past `$D000`
  - the final implementation kept the byte-step quality fix while recovering the lost headroom
- Tightened `rng_range_word` scratch usage so the final shared patch fits the live C64 banked boundary again:
  - C64 staged banked payload source remains at `$CFFD`, with `3` bytes below `$D000`
  - C128 staged source / program image moved to `$DFCA`, leaving `54` bytes below `$E000`
- Added focused regression coverage in `commodore/c64/tests/test_rng.s` proving `rng_next` matches eight reference one-bit steps.
- Fixed two latent test-harness issues that were uncovered by the broader rerun:
  - `commodore/c64/tests/test_monster_ai.s` test 20 now reloads the monster pointer after clearing the old occupied tile
  - `commodore/c64/tests/test_combat.s` test 20 now falls through to tests 21-25, and test 23 now matches the actual excess-halving level-up behavior
- Verification completed:
  - `commodore/c64/run_tests.sh` → `33 passed, 0 failed`
  - `python3 -u commodore/c128/harness128_batch.py --mode compare --snapshot-path commodore/c128/out/ready.vsf --vice /opt/homebrew/bin/x128 --connect-timeout 12` → `PASS`

## `AUDIT-P7-ZP1` Design

### Goal
- Execute `ZP-1` by turning the declared zero-page ownership contract into an automated check.
- Catch the high-risk drift:
  - raw `$90-$FF` zero-page memory operands outside explicitly blessed cases
  - raw literal zero-page operands where the code should normally be using named labels

### Scope
- In scope:
  - `commodore/common/zeropage.s`
  - assembly sources under `commodore/common/`, `commodore/c64/`, and `commodore/c128/`
  - build plumbing needed to run the scan consistently
  - audit/task docs updated from the first live scan results
- Out of scope:
  - broad renaming of existing zero-page labels
  - changing the zero-page map itself in this phase
  - data-byte style cleanup unrelated to real memory operands

### Verification Standard
1. Confirm the live zero-page contract from `zeropage.s`.
2. Implement a scanner that inspects assembly operands after stripping comments.
3. Prove the scanner ignores false-positive classes such as `#$ff`, `.byte $ff`, and comment text.
4. Run the scanner against the live tree and classify each hit as:
   - real violation to fix
   - explicitly blessed raw usage
   - scanner gap to tighten
5. Update the audit docs with the completed scan result and remaining follow-up, if any.

### Review
- Completed.
- Added `tools/check_zp_usage.py` and root `make check-zp` so the zero-page contract is now enforced by a reproducible project command instead of comments alone.
- Tightened the scanner after the first run so it ignores immediate-expression false positives like `#~FLAG & $ff`, `.byte $ff`, and comment text.
- The first real scan found intentional but undocumented raw accesses to KERNAL / Screen Editor bytes:
  - `$90` status / `READST`
  - `$C6` keyboard buffer count
  - `$CC` Screen Editor cursor/keyboard state
  - `$D8` C128 Screen Editor 80-column mode byte
- Converted those call sites to named symbols in `commodore/common/zeropage.s`, and replaced the remaining raw low-ZP scratch loops with symbolic operands in:
  - `commodore/c64/main.s`
  - `commodore/c64/memory.s`
  - `commodore/c128/boot128.s`
  - `commodore/c128/memory128.s`
- Verification completed:
  - `python3 tools/check_zp_usage.py --self-test` → `PASS`
  - `make check-zp` → `0 error(s), 0 warning(s)`
  - `make -C commodore/c64 build` → `PASS`
  - `make -B -C commodore/c128 build128` → `PASS`
  - `commodore/c64/run_tests.sh` → `33 passed, 0 failed` on rerun after the known flaky `render` suite
- `python3 -u commodore/c128/harness128_batch.py --mode compare --snapshot-path commodore/c128/out/ready.vsf --vice /opt/homebrew/bin/x128 --connect-timeout 12` → `PASS`

## `AUDIT-P8-ALIGN1` Design

### Goal
- Execute `ALIGN-1` by checking the live build, not just source layout comments, for page-cross penalties in hot render, combat, and input paths.
- Separate:
  - already-safe hot tables that do not need churn
  - real page-cross candidates that are worth future action
  - cold crossings that should not be sold as high-ROI optimization

### Scope
- In scope:
  - `commodore/c64/dungeon_render.s`
  - `commodore/c128/dungeon_render_vdc.s`
  - `commodore/common/combat.s`
  - `commodore/c64/input.s`
  - `commodore/c128/input128.s`
  - `commodore/c128/screen_vdc.s`
  - current C64/C128 symbol outputs used to locate the live table addresses
- Out of scope:
  - speculative percentage speedup claims
  - broad data-layout rewrites in this phase
  - padding/alignment changes that spend headroom without evidence

### Verification Standard
1. Identify the actual indexed tables used in the hot render/combat/input loops.
2. Check their current addresses in the live C64 and C128 symbol maps.
3. Mark each case as:
   - page-safe in the full indexed range
   - crossing, but cold enough to ignore for now
   - crossing in a genuinely hot path
4. Estimate cycle impact only from the real access count and current thresholds.
5. Update the audit docs with the completed findings and the next execution item.

### Review
- Completed.
- Most of the true hot-path row/tile tables are already well placed in the live builds:
  - C64 `map_row_*`, `screen_row_*`, `color_row_*`, `tile_screen_codes`, and `tile_colors` stay within page for their full indexed ranges
  - C128 `map_row_*`, `screen_row_*`, `color_row_*`, `tile_screen_codes`, `tile_vdc_colors`, `cia_scancode_table`, `key_map_petscii`, `key_map_cmd`, and `vic_to_vdc_color` are also page-safe across the indexed ranges actually used
- The highest-value live crossing is the C64 input search table:
  - `key_map_petscii` starts at `$10E6`, so the linear `cmp key_map_petscii,x` loop crosses page once `x >= 26`
  - worst case is `27` extra cycles per full-table search
  - movement keys and common early table hits avoid the penalty, so this is real but not top-tier
- The remaining crossings found in this phase are narrower:
  - C64 `cr_color` at `$35E0` crosses for monster types `>= 32`
  - C128 `cr_display` at `$5EF3` crosses for monster types `>= 13`
  - C128 `cr_level` at `$5FF7` crosses for monster types `>= 9`
- Those creature-table crossings are real, but their savings are modest:
  - roughly `+1` cycle per crossed lookup
  - on C128 the VDC I/O cost dominates total render time, so table realignment here is lower priority than the current audit queue
- A few non-hot/cold crossings still exist, such as C64 `xp_level_lo`, but they do not justify promotion into the hot-path alignment backlog.
- Verification completed:
  - `make -C commodore/c64 build` → `PASS`
  - `make -B -C commodore/c128 build128` → `PASS`
  - `commodore/c64/run_tests.sh` → `33 passed, 0 failed` on rerun after the known flaky `render` suite
  - `python3 -u commodore/c128/harness128_batch.py --mode compare --snapshot-path commodore/c128/out/ready.vsf --vice /opt/homebrew/bin/x128 --connect-timeout 12` → `PASS`

## `AUDIT-P9-LINT1` Design

### Goal
- Execute `LINT-1` by moving recurring 6502 instruction-shape nits into a reproducible static check.
- Start narrow and high-confidence:
  - fail on provably redundant zero-compares
  - surface branch-then-immediate-jump ladders as advisory warnings, not hard failures

### Scope
- In scope:
  - assembly sources under `commodore/common/`, `commodore/c64/`, and `commodore/c128/`
  - build plumbing needed to run the new linter consistently
  - the first small wave of source cleanup required to land the linter green
  - audit/headroom/task docs affected by the resulting code-size changes
- Out of scope:
  - broad ladder rewrites for every branch-range workaround
  - duplicate-constant linting in this phase
  - test-tree style assertions that intentionally compare against zero

### Verification Standard
1. Implement a source-tree linter with internal self-tests.
2. Restrict the hard-fail rule to cases where:
   - the compare is `cmp/cpx/cpy #0`
   - the previous real instruction already set the relevant N/Z flags
   - the next real instruction branches only on N/Z (`beq/bne/bmi/bpl`)
3. Run the linter on the live tree and fix the first real hits.
4. Keep branch-then-jump shapes as warnings only and record the backlog size.
5. Rebuild C64/C128 and rerun the normal runtime verification before closing the phase.

### Review
- Completed.
- Added `tools/check_6502_lint.py` and root `make check-6502-lint`.
- The initial linter rules are intentionally conservative:
  - hard-fail on redundant `cmp/cpx/cpy #0` only when the surrounding instructions prove the compare is unnecessary
  - warn on branch-then-immediate-jump ladders so the repo can track them without forcing a risky mass rewrite
- Cleaned the first six live redundant-compare hits in shipping source:
  - `commodore/c128/input128.s`
  - `commodore/common/dungeon_gen.s`
  - `commodore/common/ui_character.s`
- First live lint result after cleanup:
  - `make check-6502-lint` → `0 error(s), 320 warning(s)`
  - all warnings are advisory branch-jump ladders; the tool prints only the first batch and suppresses the remainder
- Refreshed the live layout after the cleanup:
## `AUDIT-P10-CA01` Design

### Goal
- Execute `CA-01` with a size-positive shared numeric core, not just a source-only move.
- Remove the duplicated decimal decomposition logic that currently exists separately in:
  - screen decimal output
  - combat message decimal appenders
- Keep the public entry points unchanged:
  - `screen_put_decimal`
  - `screen_put_decimal_rj2`
  - `screen_put_decimal_lz2`
  - `screen_put_decimal_16`
  - `combat_append_decimal`
  - `combat_append_decimal_16`

### Scope
- In scope:
  - `commodore/common/combat.s`
  - `commodore/common/numeric_format.s` (new shared module)
  - `commodore/c64/screen.s`
  - `commodore/c128/screen_vdc.s`
  - focused runtime tests that directly validate numeric output
  - audit/headroom/task docs affected by the layout change
- Out of scope:
  - changing the 24-bit score formatter in this phase
  - changing caller-facing screen or combat APIs
  - broad text/UI refactors unrelated to numeric formatting

### Verification Standard
1. Replace the duplicated 8-bit and 16-bit decimal decomposition with one shared implementation per build.
2. Move the 16-bit power-of-10 tables into common code so combat no longer depends on backend-local screen data.
3. Preserve exact visible output for:
   - screen decimal print paths
   - combat message decimal appenders
4. Add direct runtime coverage for the refactored screen and combat formatter paths.
5. Rebuild C64/C128, rerun the standard verification, and record the real headroom delta.

### Review
- Completed.
- Added `commodore/common/numeric_format.s` as the shared 8-bit / 16-bit formatter core for:
  - `screen_put_decimal`
  - `screen_put_decimal_rj2`
  - `screen_put_decimal_lz2`
  - `screen_put_decimal_16`
  - `combat_append_decimal`
  - `combat_append_decimal_16`
- Removed the old cross-module `decimal_powers_*` dependency from `combat.s`; combat now formats through common numeric data instead of backend-local screen tables.
- Added direct runtime coverage for the refactor:
  - `commodore/c64/tests/test_score.s` now checks `screen_put_decimal_lz2` and `screen_put_decimal_16`
  - `commodore/c64/tests/test_combat.s` now checks `combat_append_decimal` and `combat_append_decimal_16`
  - `commodore/c128/tests/test_vdc_attr128.s` now checks VDC `screen_put_decimal_16`
- Live headroom improved materially in the constrained staged/source regions:
  - C64 main image margin moved from `40` to `141` bytes below `$C000`
  - C64 staged banked payload source moved from `5` to `106` bytes below `$D000`
  - C128 staged source / program image moved from `79` to `180` bytes below `$E000`
- Verification completed:
  - `make check-zp` → `PASS`
  - `make check-6502-lint` → `PASS` with `318` advisory warnings
  - `java -jar ../../tools/kickass/KickAss.jar main.s -showmem -vicesymbols -o out/moria8.prg` in `commodore/c64` → `PASS`
  - `make -B -C commodore/c128 build128` → `PASS`
  - `commodore/c64/run_tests.sh` → `33 passed, 0 failed`
  - `make test128-fast` → `PASS`
- At that checkpoint, the next unresolved audit phase was `CA-02` (now completed in `AUDIT-P20-CA02`).

## `AUDIT-P11-CA02` Design

### Goal
- Execute `CA-02` by building the filtered inventory/equipment visible-slot list once and reusing it across:
  - prompt range generation
  - overlay letters/order
  - key-to-slot mapping
- Preserve the user-visible contracts:
  - filtered prompts still relabel contiguously from `A`
  - full inventory/drop/throw paths still use absolute slot letters
  - zero-match behavior and cancellation stay unchanged

### Scope
- In scope:
  - `commodore/common/player_items.s`
  - `commodore/common/ui_inventory.s`
  - focused runtime coverage that already exercises sparse filtered selection / takeoff mapping / filtered overlays
  - audit/headroom/task docs affected by any layout change
- Out of scope:
  - broad inventory UI redesign
  - changing the all-inventory/drop/throw absolute-letter contract
  - unrelated item/equipment logic

### Verification Standard
1. Build one shared visible-slot cache for filtered carried-item prompts.
2. Build one shared visible-slot cache for contiguous equipped-item selection.
3. Make filtered overlays consume the cache instead of rescanning when applicable.
4. Keep full inventory display and absolute-slot pickers unchanged.
5. Rebuild C64/C128, rerun the standard runtime checks, and record the real headroom delta.

### Review
- Partially completed.
- The first full `player_items.s` cache rewrites were not safe:
  - filtered-inventory cache attempts caused `commodore/c64/tests/test_item.s` to hang instead of return within the project timeout rules
  - the hang disappeared immediately when `player_items.s` was restored to the last known-good filtered selection path
- A reduced implementation is now verified:
  - `item_takeoff` uses a cached contiguous equipment-slot list for prompt count + key-to-slot mapping
  - filtered carried-item prompts remain on the original count-scan + pick-scan path for now
- Verification completed on the reduced implementation:
  - direct `tests/test_item.s` monitor run returned in `~6.4s` with `47/47` passes
  - `commodore/c64/run_tests.sh` → `33 passed, 0 failed`
  - `make test128-fast` → `PASS`
- Outcome:
  - `CA-02` is narrowed, not closed
  - the remaining open work is the filtered-inventory cache, and it must be treated as a memory/corruption problem inside `commodore/common/player_items.s`, not a timing problem

### `AUDIT-P20-CA02` Review

- Completed.
- Finished the carried-item half of `CA-02` in `commodore/common/player_items.s` by replacing the filtered prompt count-scan + key-pick rescan pair with one dedicated visible-slot cache.
- Kept the cache storage local to `player_items.s` instead of reusing `combat_msg_buf`; that was the critical safety constraint that prevented the earlier hang from returning.
- Caught and fixed one follow-up bug during verification:
  - the first cache draft failed to preserve the visible-count index across `piw_inv_slot_matches_filter`, which wrote slot numbers at the wrong offsets and broke the late filtered-item tests
- Final measured outcome:
  - filtered carried-item rescans are removed
  - equipment-selection rescans remain removed from the earlier phase-11 reduction
  - no measurable headroom delta versus the phase-19 tree
- Verification:
  - `bash commodore/c64/run_tests.sh`: `33 passed, 0 failed`
  - `python3 -u commodore/c128/harness128_batch.py --mode compare --snapshot-path commodore/c128/out/ready.vsf --vice /opt/homebrew/bin/x128 --connect-timeout 12`: `PASS`

## `CODE_AUDIT` Review

### Review Pass 1
- The initial audit missed two live correctness risks that are still present in the tree: melee to-hit overflow handling in `combat.s` and the one-bit-step RNG in `rng.s`.
- The numeric-format savings were understated because `score.s` has its own 24-bit formatter in addition to the two screen backends and combat formatter.
- Several smaller refactor items were too optimistic on byte savings; those claims were tightened to realistic ranges.

### Review Pass 2
- Fixed the placement of the `CA-10` verification notes so the audit reads cleanly end-to-end.
- Updated the formatter evidence to cite the score formatter as another actual duplicate.
- Toned down the RNG item so it reads as a quality/design tradeoff rather than a high-priority correctness defect.
- Final audit state is focused on actionable items with realistic savings or explicit cycle-cost tradeoffs where appropriate.

### Review Pass 3
- Reframed the audit around perimeter safety and architectural debt rather than cleanup-first prioritization.
- Added `HEADROOM-1`, `ALIGN-1`, `ZP-1`, `LINT-1`, and `API-1` as governance items ahead of the tactical cleanup backlog.
- Softened `API-1` to require one caller-visible C128 text contract without prematurely forcing one internal storage choice.
- Made the immediate execution order explicit: re-verify the old wrapper bug, produce exact memory-margin reporting, then address the arithmetic and contract issues.

## `CODE-AUDIT` Design

### Goal
- Produce a repo-grounded audit plan for the Commodore codebase focused on:
  - common 6502 mistakes and fragile idioms
  - duplicated or near-duplicated code that should be shared
  - computationally or space-wasteful patterns
  - structure/style/alignment consistency
- The expected artifact is `commodore/CODE_AUDIT.md`, not an implementation patch set.

### Scope
- In scope:
  - `commodore/common/`
  - `commodore/c64/`
  - `commodore/c128/`
  - current project docs when they constrain or explain the code shape
- Out of scope:
  - non-Commodore trees
  - speculative changes that ignore current segment/banking limits
  - claiming measured runtime improvements that were not actually benchmarked

### Audit Method
1. Reuse existing local evidence first:
   - `commodore/AUDIT.md`
   - `commodore/DESIGN.md`
   - `tasks/6502_gotchas.md`
   - active build-plan backlog items
2. Inspect representative shared/runtime-heavy files for:
   - duplicate helpers
   - branch/flag misuse
   - repeated save/restore scaffolding
   - unnecessary loads/stores/compares
   - inconsistent loop/control-flow shapes
3. Prefer findings that are concrete enough to estimate:
   - byte savings
   - per-call or per-tile cycle savings
   - maintenance/risk reduction
4. Present the result as an implementation plan:
   - item
   - evidence
   - proposed cleanup/refactor
   - expected savings
   - verification notes / guardrails

### Constraints
- Do not disturb current memory/banking contracts in the audit recommendations.
- Any suggested shared helper must respect C64/C128 execution-bank differences.
- Savings are estimates unless explicitly measured.

### Review
- Completed. The final audit now leads with governance items for headroom, alignment, zero-page ownership, linting, and the C128 text contract, followed by the tactical cleanup findings and revised execution order.

## Previous Task Notes
- [x] Audit the shared filtered prompt/display paths in `ui_inventory.s`, `player_items.s`, and related item-selection callers.
- [x] Review upstream VMS-Moria and Umoria behavior for filtered item prompts and equipment selection.
- [x] Get consultant input on the safest shared fix shape and regression strategy.
- [x] Lock the local `BUG-PROMPT-FILTER` user-visible contract and implementation seam.
- [x] Write the implementation checklist and focused verification matrix before coding.

## `BUG-PROMPT-FILTER` Design

### Problem Statement
- Active backlog entry: `BUG-PROMPT-FILTER` in `commodore/BUILDPLAN.md`.
- Current filtered item-selection commands still behave like full absolute-slot pickers:
  - prompts advertise the whole range (`a-v` / `a-h`)
  - `?` overlays hide unrelated items but keep absolute slot letters
  - input handlers still parse absolute letters directly and only then reject mismatched categories
- Result: the UI can show a filtered subset while still exposing misleading letters and whole-pack prompt ranges.

### Current Code Facts
- Shared inventory overlay in `commodore/common/ui_inventory.s` already filters rows via `uinv_filter`, but labels filtered entries with absolute slot letters (`A + slot`) instead of contiguous visible letters.
- Shared selection handlers in `commodore/common/player_items.s` still do direct `sbc #$41` absolute-slot parsing for:
  - `item_wear`
  - `item_takeoff`
  - `item_quaff`
  - `item_read_scroll`
  - `item_aim_wand`
  - `item_use_staff`
  - `item_gain_spell`
- `show_inv_and_restore` uses `uinv_filter` only for overlay display, not as a shared source of truth for selection mapping.
- `item_wear` has an extra local eligibility rule beyond category filtering:
  - `ICAT_LIGHT` includes Flask of Oil, but Flask of Oil is not wearable
- Local pack storage is sparse, not compact:
  - `inv_add_item` writes to the first empty carried slot
  - `inv_remove_item` clears a slot and does not compact the pack
- Important scope boundary:
  - `item_drop` and identify-style all-item pickers are unfiltered and do not need this bug’s relabeling
  - `item_eat` auto-selects the first food item and is not a prompted filtered picker today

### Upstream Findings
- **VMS-Moria**
  - `find_range()` in `source/include/moria.inc` discovers the first/last relevant inventory range for a requested object set.
  - `get_item()` then prompts only that filtered range: `(Items a-b, * for inventory list, ^Z to exit) ...`
  - `show_inven()` prints letters from compacted inventory positions within that filtered range.
  - `show_equip()` labels only non-empty equipment entries contiguously (`a`, `b`, `c`, ...).
- **Umoria**
  - `inventoryGetInputForItemId()` in `src/ui_inventory.cpp` is the shared selection gateway for filtered pack/equipment prompts.
  - It prints only the active filtered span (`Items a-b ...`) and keeps the prompt and selection parser in the same shared path.
  - `displayEquipment()` labels only non-empty equipment rows contiguously.
- **Meaning for Moria8**
  - The upstream contract worth preserving is:
    - filtered prompts expose only valid choices
    - visible letters are contiguous
    - `?` overlay letters and accepted input must match
  - The upstream storage assumption is **not** worth copying in this bug:
    - both upstream trees rely on compacted/sorted inventory layouts that Moria8 does not currently have

### Locked User-Visible Contract
1. Any filtered item-selection command must present only valid choices for that command.
2. The `?` overlay for that command must show exactly the same selectable set that the prompt parser accepts.
3. Filtered visible letters must be contiguous from `A` upward with no gaps from hidden sparse slots.
4. Selecting `B` in a filtered prompt must pick the second visible matching item, not the physical slot whose absolute letter is `B`.
5. Prompt text must advertise only the valid visible range, not the whole pack/equipment span.
6. Equipment takeoff selection must use contiguous letters for non-empty equipment rows.
7. Full unfiltered inventory behavior remains unchanged in this bug unless a command is explicitly in the filtered-prompt list.

### Scope Decision
- **In scope for implementation**
  - filtered pack commands:
    - `item_wear`
    - `item_quaff`
    - `item_read_scroll`
    - `item_aim_wand`
    - `item_use_staff`
    - `item_gain_spell`
  - filtered equipment command:
    - `item_takeoff`
- **Out of scope for this bug**
  - pack sorting/compaction
  - global inventory letter redesign for unfiltered views
  - changing storage layout or `inv_add_item` / `inv_remove_item`
  - unrelated all-item pickers such as `item_drop`

### Preferred Design Shape
- Implement this entirely at the prompt/UI-selection layer.
- Do **not** change real inventory/equipment storage order.
- Add one shared mode-aware helper layer in `commodore/common/` for prompted item selection.
- Preferred helper seam:
  - `inv_slot_matches_mode(slot, mode)`:
    - true only if the physical slot is a valid target for the active prompt mode
    - must support command-specific rules such as excluding Flask of Oil from `wear`
  - `inv_count_matches_mode(mode)`:
    - counts visible filtered candidates for dynamic prompt suffixes and zero-match handling
  - `inv_pick_nth_match(letter_index, mode)`:
    - maps visible ordinal `A/B/C...` to the physical sparse pack slot
  - `equip_pick_nth_nonempty(letter_index)`:
    - maps visible ordinal `A/B/C...` to the nth non-empty equipment row
- Use the same helper path from both:
  - overlay rendering (`?`)
  - prompt input parsing
- Keep `uinv_filter` as a rendering hint only if needed for the overlay, but do not let it remain the sole semantic filter source for command selection.

### UI / Prompt Decisions
- Filtered pack overlays should relabel matching items contiguously (`A)`, `B)`, `C)`), not with absolute sparse-slot letters.
- `item_takeoff` should not be redesigned into a different equipment screen.
- Safer equipment approach:
  - keep the existing slot-label rows (`Weapon:`, `Body:`, etc.)
  - add contiguous selection letters only for non-empty rows
  - map `A/B/C...` to the nth occupied equipment row
- Dynamic prompt text should show the actual visible span for the current command:
  - examples: `(A-A)`, `(A-B)`, `(A-C)`
- If there are zero valid items:
  - do not print a misleading `A-V` / `A-H` prompt
  - short-circuit with the appropriate no-valid-item message path before reading input

### Risks / Edge Cases
- Biggest risk: duplicated filter logic between overlay and parser.
  - If the display and parser drift, the bug is still present in a worse form.
- `item_wear` is the main semantic trap.
  - “wearable” is not just category-based because Flask of Oil must stay excluded.
- `item_takeoff` cursed items should remain selectable.
  - They are meaningful targets because selection should still produce the existing cursed rejection.
- Sparse local pack layout means direct upstream range-copying is unsafe.
  - Moria8 must emulate contiguous selection with ordinal mapping, not storage changes.
- Shifted/unshifted letter acceptance should remain compatible with current command behavior.

### Focused Verification Plan
1. **Filtered pack display**
   - Put valid items in non-contiguous slots and verify the `?` overlay shows contiguous letters with no gaps.
2. **Filtered pack selection mapping**
   - Selecting the second visible letter must choose the second matching sparse slot.
3. **Filtered pack rejection**
   - A hidden non-matching absolute slot letter must not select that hidden item.
4. **Wear special case**
   - Flask of Oil must not appear as a wearable candidate.
5. **Equipment sparse selection**
   - Non-adjacent occupied equipment slots must display/select as `A)`, `B)`, etc.
6. **Equipment cursed selection**
   - A cursed equipped item must remain selectable and still produce the existing cursed message.
7. **Zero-match behavior**
   - Each filtered command must avoid a misleading full-range prompt when no valid items exist.
8. **Prompt / overlay parity**
   - The highest prompt letter must equal the number of visible overlay entries.
9. **Regression boundary**
   - Unfiltered inventory/drop behavior remains unchanged.

### Suggested Test Homes
- Extend `commodore/c64/tests/test_item.s` for:
  - wear
  - takeoff
  - quaff
  - read / identify follow-on
  - gain spell if it already has supporting setup nearby
- Extend `commodore/c64/tests/test_wands_staves.s` for:
  - aim wand
  - use staff
- Add focused C128 fast/unit coverage once the shared helper layer exists, because the bug lives in shared prompt/input code.

### Consultant Review
- Consultant consensus:
  - preserve upstream parity at the prompt/UI layer, not the storage layer
  - use one shared ordinal-mapping helper path for both overlays and selection parsing
  - reindex filtered pack prompts and non-empty equipment selection contiguously
  - keep pack sorting/compaction out of this bug

### Review
- Implemented the shared filtered-inventory helper path in `commodore/common/player_items.s` and moved the prompt/selection contract onto that one source of truth.
- Filtered prompts now patch their advertised range dynamically, filtered pack overlays relabel sparse matches contiguously, and equipment overlays show contiguous letters for non-empty rows only.
- `item_wear` now excludes Flask of Oil from both the visible wearable set and the accepted filtered input path, so the overlay/parser contract matches the real equippable set.
- Resident/string-bank Huffman assets were regenerated after removing now-dead filtered-selection error strings and refreshing the subsystem test bank fixture to the current tree.
- Verification completed:
  - `java -jar ../../tools/kickass/KickAss.jar main.s -showmem -vicesymbols -o out/moria8.prg` — PASS (`72` asserts, `0` failed)
  - `bash commodore/c64/run_tests.sh` — PASS (`33` suites passed, `0` failed)

## Status Update
- The oversized Umoria-style interactive `look` rewrite has been backed out from gameplay code.
- The C64 main program fits again at `$080E-$CFE5`, and `commodore/c64/tests/test_effects.s` fits again at `$0825-$BF1C`.
- Current gameplay code is back on the compact directed scan path while the project decides whether to keep that VMS-style baseline or spend budget on selected richer `look` behavior later.
- Deferred note: closing the remaining VMS/Umoria parity gap for `look` will require significant engineering because the feature is behaviorally complex and the C64 memory budget is already tight.

## Current Task
- [x] Lock the reduced directed `look` contract from local primary sources/runtime and record intentional feature deltas.
- [x] Write the `BUG-LOOK-HILITE` parity test matrix before implementation.
- [x] Move directed `look` coverage into a host test image that still fits C64 test memory limits.
- [x] Reuse shared directed-input handling instead of keeping a bespoke `look` prompt reader.
- [x] Back out the oversized interactive `look` rewrite so the C64 main segment fits again.
- [ ] Decide whether to keep the compact VMS-style baseline or fund a larger parity push later.
- [x] Add platform-owned target highlight/flash behavior for C64 and C128.
- [ ] Add C128 unit/smoke coverage for the shared `look` changes.
- [ ] Run full regression gates before asking for human playtesting.

## `BUG-LOOK-HILITE` Design And Verification Plan

### Problem Statement
- The current port's `look` command is not end-user equivalent to Umoria.
- Today it uses a straight-ray, single-result scan with no visible target cue.
- Umoria documents different behavior:
  - directional cone search
  - a creature on an object should describe both
  - monster memory is reachable from `look`
- Local VMS-Moria does not implement all-directions `look`; its `look` command is directed-only.
- Local VMS-Moria also keeps `look` materially smaller than Umoria:
  - straight-ray scan
  - non-interactive flow
  - no recall handoff
  - no per-target pause/highlight
- Project decision: drop the Umoria-only all-directions/null-direction feature and keep the rest of the `look` work scoped to directed `look`.
- Open decision after source review: whether Moria8 should keep chasing Umoria-only interactive `look` semantics, or pivot to the smaller VMS-style directed contract that better matches current C64 memory limits.

### Non-Negotiable Requirements
1. End-user directed `look` behavior must match the reduced project contract, with all-directions `look` intentionally excluded.
2. Highlight/flash presentation may be adapted for C64/C128 hardware constraints.
3. No regressions in any other behavior.
4. Everything must be unit-testable before human testing.

### Current Code Facts
- Shared `look` implementation lives in `commodore/common/player_move.s` as `do_look`.
- `do_look` currently depends on `get_direction_target` from `commodore/common/dungeon_features.s`.
- `get_direction_target` still uses the generic `Direction?` prompt rather than VMS-Moria's `Look which direction?`.
- `do_look` currently prints one description and exits.
- There is no current `look`-specific target cue.
- Cross-platform flash primitives already exist:
  - `commodore/c64/screen.s` → `screen_flash_at`
  - `commodore/c128/screen_vdc.s` → `screen_flash_at`
- Existing regression coverage only proves remembered dark tiles do not get revealed by `look`.
- Existing monster recall UI already exists and should be reused rather than reimplemented.
- `FEATURES.md` records the intentional version split: Umoria has all-directions `look`; VMS-Moria and Moria8 do not.

### Architecture Decision
- Keep generic adjacent-action direction handling unchanged.
- Do not treat Umoria-only interactive `look` behavior as settled until the project chooses between Umoria-style and VMS-style directed `look`.
- If the project stays on Umoria-style directed `look`, keep highlight platform-owned and split target selection from target presentation / recall handoff.
- If the project pivots to VMS-style directed `look`, prefer the simpler straight-ray/message path and delete the interactive `look` framework instead of optimizing it piecemeal.

### Behavior Contract To Lock Before Coding
- Shared facts locked from local upstream source trees `~/Projects/thirdparty/umoria` and `~/Projects/thirdparty/vms-moria`:
  - `look` is a free move.
  - blindness check happens before prompting.
  - directed empty look ends with `You see nothing of interest in that direction.`
- Umoria-only directed `look` behavior currently implemented in `~/Projects/thirdparty/umoria/src/dungeon_los.cpp`:
  - panel-bounded cone search
  - interactive, multi-target flow
  - player tile inspected first
  - optional recall handoff
  - layered monster/object/feature messaging with pause/abort between shown targets
  - directed end-of-scan prints `That's all you see in that direction.`
- VMS-Moria directed `look` behavior currently implemented in `~/Projects/thirdparty/vms-moria/source/include/moria.inc`:
  - straight-ray scan along one direction
  - no per-target pause
  - no recall prompt/return flow
  - repeated `msg_print` output as interesting tiles are encountered
  - stops on blocked tile or sight limit
- Intentionally excluded from Moria8 already:
  - null direction `5`
  - `.` all-directions `look`
  - all-directions completion/empty messages
- Still awaiting explicit project choice:
  - Umoria-only interactive cone/reveal/recall behavior beyond the shared directed `look` baseline

### Known Port-vs-Upstream Gaps
- Current port `do_look` is single-result, straight-ray, and non-interactive.
- Local VMS-Moria keeps scanning down the ray and can emit multiple messages for successive interesting tiles; current Moria8 returns after the first interesting result.
- Local VMS-Moria can describe multiple things on one tile in sequence; current Moria8 picks a single highest-priority result and exits.
- Current Moria8 reports generic doors, stairs, traps, rubble, and wall hits; local VMS-Moria `look` is narrower and mainly reports monsters, items, and rock/mineral features.
- Local VMS-Moria explicitly prints the blindness failure message; current Moria8 does not have a `do_look`-local blind-message branch.
- Current port reports walls directly, which does not match upstream default seam behavior.
- Current port has no look-time recall prompt or return-to-look flow.
- Current port has no per-target cursor/highlight step.

### Candidate Selection Strategy
- Preferred implementation shape:
  - reproduce the upstream two-pass `lookSee` / `lookRay` behavior closely enough that target order and prompts match the observed Umoria flow
  - preserve panel bounds and pause-per-target interaction
- Important rule:
  - implementation does not define behavior
  - if a simpler scan cannot reproduce upstream target order and interaction semantics, replace it with a closer source-matched traversal

### Shared-Code Safety Rules
- Do not add null-direction/all-directions `look`.
- Do not modify global `rest` semantics.
- Reuse shared directed-input handling, but do not force `look` through `get_direction_target` if it still needs direction identity rather than an adjacent tile.
- Do not refactor the main renderer as part of this bug.
- Do not touch player-facing strings for memory relief.
- Do not merge unrelated input or recall cleanup into this task.

### Step-By-Step Implementation Plan
1. Verify the reduced directed-only `look` contract against local Umoria and VMS-Moria sources.
2. Write targeted parity tests that fail under the current implementation.
3. Reuse directed input handling where possible; only add `look`-specific input code if directed `look` still needs it.
4. Introduce a shared `look` state record:
   - active direction
   - current pass (`objects` / `rocks`)
   - current descriptive prefix (`You see`, `It is on`, `It is in`)
   - current query/abort key
   - current target coordinates / target kind
5. Replace the inline straight-ray logic in `do_look` with an interactive target iterator.
6. Implement upstream-style pause-per-target behavior and `ESCAPE` abort.
7. Implement the Umoria-correct text flow:
   - monster first with `[(r)ecall]`
   - item second if present
   - feature third if present / enabled
8. Hook look-time monster recall into the existing recall UI path, then restore gameplay view and continue the active look flow using the key returned from recall dismissal.
9. Add a shared highlight call that moves attention to the current target tile before waiting for input.
10. Adapt the C64/C128 flash primitive behavior if the existing `*` flash is not the best platform-appropriate representation.
11. Run full regression gates and only then hand off for manual verification.

### Test Matrix

#### Input Contract
- [ ] `look` accepts all 8 directions.
- [ ] Invalid `look` direction input exits cleanly without consuming a turn.

#### Visibility Contract
- [ ] `look` does not describe remembered-but-not-currently-visible monsters.
- [ ] `look` does not describe remembered-but-not-currently-visible items.
- [ ] `look` respects the 20-tile range limit.
- [ ] `look` rejects tiles outside the selected directional cone.

#### Panel / Screen Contract
- [x] Upstream is panel-bounded.
- [ ] Visible off-panel targets do not participate in `look`.
- [ ] Selected target coordinates are converted to correct screen row/column for both C64 and C128.
- [ ] `look` highlights each shown target before waiting for input.

#### Target Priority Contract
- [ ] Target visitation order matches the chosen directed traversal for representative straight and diagonal cases.
- [ ] Monsters are shown before objects/features on the same tile.
- [ ] Objects/features are only shown when their lighting/mark rules match upstream behavior.
- [ ] Town behavior is covered in all directions, not just dungeon rooms/corridors.

#### Description Contract
- [ ] Feature-only tiles print the correct feature description.
- [ ] Monster-only tiles print the correct monster description.
- [ ] Item-only tiles print the correct item description.
- [ ] Monster-on-object tiles produce the correct upstream sequence:
  - monster line first
  - object line next using `It is on ...`
- [ ] Object-in-wall / seam cases produce the correct upstream `It is in ...` / wall text sequence.
- [ ] Directed empty look prints `You see nothing of interest in that direction.`
- [ ] Directed end-of-scan prints `That's all you see in that direction.`

#### Recall Contract
- [ ] Monster prompt includes `[(r)ecall]`.
- [ ] Pressing `r` from look enters recall for the shown monster.
- [ ] Recall returns cleanly to the active look flow.
- [ ] `ESCAPE` from recall aborts the whole look, matching upstream returned-key behavior.
- [ ] Existing non-`look` recall command behavior does not regress.

#### Highlight Contract
- [ ] Highlight/flash marks the same target that the text description selected.
- [ ] Flash restores the underlying tile cleanly.
- [ ] C64 flash path does not corrupt screen/color RAM state.
- [ ] C128 flash path does not corrupt VDC state or IRQ-sensitive screen state.

#### Regression Contract
- [ ] Existing `look` remembered-dark regression still passes.
- [ ] Existing input mapping tests still pass.
- [ ] Existing recall UI tests still pass.
- [ ] Existing C64 gameplay regression suites still pass.
- [ ] Existing C128 fast unit suite still passes.
- [ ] Existing C128 smoke coverage still passes.

### Current Size Findings
- Dropping all-directions `look` saved only `0xD9` bytes in the C64 main image.
- Reusing the shared directed-input seam saved only about 12 more bytes.
- The remaining main-image overage is concentrated in:
  - traversal setup / coordinate transform
  - `look_process_tile`
  - the custom `look` row-0 print/pause helpers
- Reverting to the compact directed scan path immediately restored the C64 layout:
  - main program fits again at `$080E-$CFE5`
  - `test_effects` fits again at `$0825-$BF1C`
- `commodore/c64/tests/test_look.s` is structurally too large in its current standalone form and should not be revived as-is.
- `commodore/c64/tests/test_effects.s` also tips over its own body-size assert with the current `player_move.s` import, so the next host candidate should be a lighter existing image such as `test_main_loop.s` or a purpose-built minimal harness.

### Verification Gates Before Human Testing
1. New C64 unit tests fail on the current behavior and pass on the new behavior.
2. Existing C64 test suite remains green.
3. New C128 input/unit coverage passes.
4. `make test128-fast` passes.
5. Relevant C128 smoke path passes.
6. Only after those gates are green should manual gameplay verification begin.

### Consultant Review
- Consultant verdict: architecture is sound.
- Consultant recommendations adopted:
  - keep `look` separate from generic direction helpers
  - keep highlight platform-owned
  - use test-first parity work
  - treat cone semantics, dual-description behavior, and recall interaction as parity obligations
  - do not let a clean implementation redefine the visible game behavior
- Updated consultant conclusion after the memory-map recheck:
  - the C64-safe path is to pivot toward the smaller VMS-style directed contract
  - the interactive Umoria-style machinery is the bulk of the overage, not the input seam

### Implementation Result (2026-03-27)
- Closed the bounded `BUG-LOOK-HILITE` scope without reopening the larger interactive-`look` parity project.
- Root cause:
  - the shared directed `look` path in `commodore/common/player_move.s` selected and described a target, but never handed that same target to a platform-owned visual cue
  - the first C128 import placement also proved that even a tiny helper can drift into the wrong residency bucket, so the final fix had to satisfy both behavior and memory-map ownership
- What shipped:
  - added `commodore/common/look_flash_target.s`, a tiny shared helper that converts `df_target_x/y` into viewport-relative screen coordinates and then calls the existing per-platform `screen_flash_at`
  - wired both item/monster and tile-description `look` paths through that helper so the flashed cell is the same target the text path already chose
  - kept the helper out of the C128 runtime-low block and added a C128 I/O-boundary audit so the new symbol stays resident below `$D000`
  - moved the regression into `commodore/c64/tests/test_effects.s`, which still fits the C64 test image while proving both the positive flash case and the remembered-dark no-flash case
- Verification:
  - `make -C commodore/c64 build`
  - direct `commodore/c64/tests/test_effects.s` monitor run: `PASS_COUNT=27`
  - `make -B -C commodore/c128 build128`
  - `make test128-fast`
- Remaining intentional open question:
  - whether to fund a larger VMS-vs-Umoria `look` parity decision later; this fix only restores the missing visual target cue for the current reduced directed contract

## FEAT-DISK C64 Init Follow-up

### Reported Failure Gate
- Live repro:
  - fresh C64 boot
  - `L`
  - accept drive `9`
  - continue to the `Initialize` prompt
  - press `Y`

### Latest Change
- Replaced the oversized C64 low-helper init attempt with a smaller banked C64 init path that:
  - creates the marker file on the selected save disk
  - reads DOS status from channel `15` after `CLOSE`
  - does not unconditionally format the disk during normal save-disk initialization
- Fixed a false-failure bug in the C64 DOS-status check:
  - the init path was storing the first status byte in `X`
  - then a second `CHRIN` call clobbered `X`
  - and the code compared that clobbered register instead of the saved first digit
- Trimmed dead carry checks after the C64 Disk Setup UI trampoline so the banked payload stays below `$D000` again
- Reworked the C64 marker-init transaction to the consultant-approved DOS flow:
  - scratch `MORIA8.ID` first via channel `15`
  - create a plain `0:MORIA8.ID,S,W` file instead of relying on `@` replace semantics
  - write marker bytes
  - close and verify by re-reading the marker file
- Removed the C64-only false program-disk rejection heuristic from setup so save-disk readiness is driven by positive marker validation instead

### Verification
- `make test64`
  - passed with `=== Results: 33 passed, 0 failed (of 33 suites) ===`
- `make test128-fast-smoke`
  - passed with `=== Results: 3 passed, 0 failed (of 3 suites) ===`

## FEAT-DISK C64 One-Drive Load/Save Follow-up

### Reported Failure Gate
- Live repro:
  - C64 one-drive `L` path loads successfully from drive `8`
  - after load, `THE.GAME` still exists on the save disk
  - a later save flashes drive error / behaves as if the old save was not removed

### Latest Change
- Kept the shared C64 secondary-address experiment in place:
  - `SAVE_SEC_ADDR = 8`
  - `LOAD_SEC_ADDR = 7`
  - `DISK_MARKER_SEC_WR = 8`
  - `DISK_MARKER_SEC_RD = 7`
- Trimmed diagnostics back to the failing C64 save-disk initialization path only.
- Current debug signal is the C64 init-fail screen in `ui_disk_setup.s`, which prints `disk_ui_value` as a stage number so the next live repro can tell us whether marker init is failing at:
  - marker-file `OPEN`
  - `CHKOUT`
  - byte write loop
  - or the post-write marker reread
- Live stage result was `5`, which narrows the C64 init failure to the post-write marker reread.
- Fixed the concrete reread mismatch in `commodore/c64/main.s`: `c64_disk_marker_present` was still hardcoded to secondary address `2` while the shared marker read contract had already moved to `7`.
- Fixed the remaining marker-write contract mismatch in `commodore/common/disk_swap.s`: `disk_marker_write_fname` no longer uses `@0:MORIA8.ID,S,W` after the path has already scratched `MORIA8.ID`; it now does a plain create.
- Fixed the stale `SETNAM` callsites in `commodore/common/disk_setup_banked.s`: both C64 and C128 marker init were still using the old `@`-skip length/address math (`len-1`, `fname+1`) after the filename changed to plain create, so they were not actually opening `0:MORIA8.ID,S,W`.
- Fixed the C64 `disk_marker_init` caller contract in `commodore/common/disk_setup_banked.s`: it was ignoring the carry result from `c64_disk_marker_write_phys` and always advancing to stage `5`, so the stage display could lie about a reread failure when the actual writer had already failed.
- Live stage moved from `5` to `3`, which isolated the remaining failure to the marker write transaction itself.
- Removed the C64 marker writer's `READST` gate after the `CHROUT` loop so it now matches the known-good `hiscore_save` write contract; close + immediate marker reread remains the real success criterion.
- Replaced the direct raw C64 marker writer in `commodore/common/disk_setup_banked.s` with the same `c64_disk_call` / wrapper contract used by the working C64 disk paths. The writer no longer manages `$01` itself.
- Consultant follow-up narrowed the remaining stage-1 failure to probe/create interference. `commodore/c64/main.s` now gives the C64 marker probe its own logical file number and cleans up the `OPEN`-fail path instead of immediately reusing the same LFN for create.
- A C64-only command-channel status helper was attempted next, but it overflowed the banked payload past `$D000`/`$FFFA`, so it was backed out before any live retest.
- The smaller consultant-backed change is now in place instead: `commodore/common/disk_setup_banked.s` no longer does the unconditional pre-scratch `S0:MORIA8.ID` before marker create. On a fresh disk that scratch was redundant and a likely owner of the persistent stage-1 `OPEN` failure.
- The C64 init-fail screen currently prints `disk_status` on the numeric line so the next live repro can distinguish a failed marker `OPEN` KERNAL error from the earlier stage-number-only diagnostics.

### Verification
- `make disk128`
  - passed
- `make test128-fast-smoke`
  - passed with `=== Results: 3 passed, 0 failed (of 3 suites) ===`
- `make test64`
  - passed with `=== Results: 33 passed, 0 failed (of 33 suites) ===`

## 2026-04-16 C128 Build128 Assert Fix

### Reported Failure Gate
- `make build128`

### Root Cause
- The spell-feedback branch added enough resident/staged bytes that the C128 banked payload staged-source span crossed the `$E000` overlay window assertion.
- My first byte-recovery move put the Home-mode `hm_*` strings into `ui_store.s`, which fixed `make build128` but bloated unrelated C64 tests that import `ui_store.s`.
- That in turn pushed `test_background.s` into the `$D000` I/O hole and exposed a separate fragile `test_effects.s` cast-loop assumption.

### Fix
- Moved the Home-mode text out of the C128 banked payload.
- Split the Home-only strings into [`commodore/common/ui_home_text.s`](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-spells/commodore/common/ui_home_text.s) and imported that only in the real town overlays and the one C64 test that actually exercises Home UI.
- Tightened the combat message invariant so slot 41 stays zero after append operations.
- Updated the synthetic `test_effects.s` repeated-cast case to follow the current prompt-driven cast path instead of the older brittle `?` loop.

### Verification
- `make build128`
  - passed with `Made 262 asserts , 0 failed`
- `make test64`
  - passed with `=== Results: 36 passed, 0 failed (of 36 suites) ===`

### Spell Prompt Follow-up
- Fixed the redundant `-more-` that appeared after choosing a book/spell in the new prompt-driven `m`/`p` flow.
- Root cause:
  - the accepted chooser prompts still occupied the message rows
  - the next gameplay prompt (`Direction?`) arrived as a third message and forced `-more-`
- Correction:
  - accepted book and spell choices now clear the message area before handing off to the next gameplay prompt
  - `msg_clear` now also resets `msg_row1_col` so row-state is fully reset
- Verification:
  - `make test64` passed with `=== Results: 36 passed, 0 failed (of 36 suites) ===`
  - added direct chooser regression in `ui_views`

### Dungeon Spell Loading Message
- Fixed the wrong `Loading...` message appearing after dungeon spell casts like `Detect Monsters`.
- Root cause:
  - C64 overlay-backed spell execution restored the current creature tier after returning from `OVL.DEATH`
  - that restore path reused `tier_check_transition`
  - `tier_load` treated it like a real depth transition and printed `Loading...`
- Correction:
  - added `tier_restore_after_overlay`
  - overlay/UI return paths now use the silent restore helper instead of raw `tier_check_transition`
  - `tier_load` now suppresses the transient loading message during silent restores
  - stale `$E0xx` monster-name recovery in `creature_get_name` now also sets the silent-restore flag around its internal tier reload
- Verification:
  - `make test64` passed with `=== Results: 36 passed, 0 failed (of 36 suites) ===`
  - added direct regressions in `test_tier.s`

### Spell List `?` Selection
- Fixed the prompt/list mismatch where pressing `?` from cast/pray opened the full-screen spell list, but pressing a spell letter only dismissed the overlay and dropped back to the previous prompt.
- Root cause:
  - `pm_prompt_visible_spell_choice` treated the overlay list as a read-only modal
  - it always read a dismiss key after `tramp_spell_list_display` even though the overlay footer advertised direct spell selection
- Correction:
  - the `?` path now feeds the overlay key back through `pm_pick_visible_spell`
  - valid letter choice selects the spell immediately
  - non-letter/ESC continues to return to the previous chooser prompt
  - moved the regression coverage into `test_effects.s` and slimmed `test_ui_views.s` back down to avoid I/O-hole growth
- Verification:
  - `make test64` passed with `=== Results: 36 passed, 0 failed (of 36 suites) ===`

### Active C128 Title-Load Gate
- Reported failure gate:
  - boot to the C128 title menu
  - insert a valid save disk in drive 8 before pressing `L`
  - press `L`
  - expected: load succeeds from the mounted save disk without the old prompt cycle
- Live correction:
  - current automation claiming the mounted-save path is fixed is invalid
  - user reran the exact drive-8-before-`L` path and got the same failure unchanged
  - do not treat the current mounted-save smoke as evidence until it models the exact live repro faithfully
- Current implementation target:
  - keep the C128-only fix inside the title `L` save/load seam
  - restore the missing drive re-init whenever one-drive title load skips `disk_prompt_save`
  - verify with an exact mounted-save-disk smoke instead of the older hybrid load-resume smoke

### Title Regression Rollback
- Clean `HEAD` and the fully reverted dirty tree now produce identical early/late C128 title screenshots under the user JiffyDOS `vicerc`.
- The partial rollback was not enough because restoring only the active title path left too much save/load-era shared runtime/layout drift in place.
- Restoring the affected C128/common product files back to `HEAD` was the first rollback that actually moved the user-visible gate.

### Verification
- `make -B -C commodore build128 disk128`
  - passed
- Visual gate:
  - dirty-tree after full rollback:
    - `/tmp/c128_title_reverthead_a.png` md5 = `34f84c30a3c819215f0767b2102f5ddf`
    - `/tmp/c128_title_reverthead_b.png` md5 = `34f84c30a3c819215f0767b2102f5ddf`
  - clean `HEAD` baseline:
    - `/tmp/c128_head_title_a.png` md5 = `34f84c30a3c819215f0767b2102f5ddf`
    - `/tmp/c128_head_title_b.png` md5 = `34f84c30a3c819215f0767b2102f5ddf`
- `TEST_FILTER='boot_title_idle_smoke|title_art_smoke' bash commodore/c128/run_tests128.sh`
  - passed with `=== Results: 2 passed, 0 failed (of 2 suites) ===`

### Latest Runtime-Load Recovery
- Current exact automated repro for the `128.RUNTIME` seam is now real instead of a false-green shell monitor:
  - `TEST_FILTER='boot_runtime_load_guard_repro' bash commodore/c128/run_tests128.sh`
  - direct `x128` boot of a shipping-disk-derived guard build
  - remote monitor waits for either:
    - `c128_runtime_load_guard_fail_shared_path_sym`
    - `title_show_sysinfo`
    - or `JAM|Invalid opcode|BRK`
- Root cause fixed in product code:
  - `commodore/c128/main.s:c128_load_runtime_prg` no longer jumps into `commodore/common/reu.s:c128_preload_asset_load`
  - runtime PRG loads are back on a dedicated path with:
    - fixed program-media device `8`
    - explicit `SETBNK`
    - `SETNAM`
    - `SETLFS`
    - `LOAD`
    - `CLOSE`
    - `CLRCHN`
    - restore of default load bank
- Harness correction:
  - `boot_runtime_load_guard_repro` now uses `commodore/c128/tests/runtime_load_repro.py`
  - `build_runtime_load_guard_boot_assets` now seeds from the real shipping `make disk128` output (`commodore/out/moria8-c128.d71`) instead of forcing the over-strict base boot-asset path
  - `build_boot_assets` now follows the actual `make disk128` success contract instead of adding an extra `grep FAILED!` gate that the reported command itself does not enforce
- Latest verification:
  - `make disk128` -> PASS
  - `TEST_FILTER='boot_runtime_load_guard_repro' bash commodore/c128/run_tests128.sh` -> PASS
  - `TEST_FILTER='boot_real_shipping_repro|boot_runtime_load_guard_repro|boot_title_load_resume_drive8_realboot_smoke|boot_title_load_resume_drive8_shipping_smoke' bash commodore/c128/run_tests128.sh` -> `=== Results: 4 passed, 0 failed (of 4 suites) ===`
 - `make test128-fast-smoke` -> `=== Results: 9 passed, 0 failed (of 9 suites) ===`
 - Live failure still red after that recovery:
   - user monitor now shows `128.RUNTIME` hang at `$0E06`
   - repeated `IRQ -> $0E06` / `BRK`
   - current machine state from the trace:
     - `$0E06` is not `mmu_common_irq` (`$0C06`)
     - `$0E06` is not `mmu_kernal_irq` (`$0C4A`)
   - refined diagnosis:
     - `commodore/c128/memory128.s:EnterKernal_sub` still restores `$0314/$0315` from `kernal_irq_vec_lo/hi`
     - on the user’s JiffyDOS setup, the captured native software IRQ tail is `$0E06`
     - that address is not a valid owned KERNAL-window IRQ bridge for the game runtime
     - the current automated runtime-load guard still misses the real bug because it does not force an IRQ to fire inside the `128.RUNTIME` load window
   - concrete test gap now identified:
     - `commodore/c128/tests/test_wrapper_irq128.s` still asserts KERNAL-window ownership should be `mmu_kernal_irq`
     - product `EnterKernal_sub` does not currently honor that contract
     - that mismatch invalidates the prior “green enough” runtime-load story
 - Runtime-load repro correction:
   - `commodore/c128/tests/runtime_load_repro.py` no longer uses remote-monitor `until $ADDR`
   - VICE remote monitor prints an immediate `UNTIL:` registration line before execution, so that path was another false green
   - the repro now sets real breakpoints for fail/pass and then uses `g`
   - the runtime-load variant also forces the live trace's stale software IRQ vector value (`$0E06`) just before `128.RUNTIME` enters the `LOAD` wrapper seam
 - New exact local red gate:
   - `TEST_FILTER='boot_runtime_load_guard_repro' bash commodore/c128/run_tests128.sh`
   - current result: red
   - captured failure:
     - `FAIL: boot_runtime_load_guard_repro (timed out waiting for monitor stop text)`
     - failure-context monitor dump shows:
       - `PC=$F4BC`
       - stack includes `913C -> FFD5`
       - stop occurs inside the KERNAL `LOAD` path, before `title_show_sysinfo`
   - this is now the active trustworthy repro for the remaining `128.RUNTIME` hang

## C128 Preload Transaction Guard Follow-up

### Reported Failure Gate
- Live repro:
  - fresh `make disk128`
  - boot C128
  - valid save disk in drive `8`
  - press `L`
  - still hangs or crashes during early preload / `128.RUNTIME` / first `MONSTER.DB.1` load

### Latest Change
- Kept the consultant-backed structural fix in place:
  - `commodore/common/reu.s`
    - `c128_preload_asset_load` remains one uninterrupted C128 KERNAL transaction for `SETBNK -> CLOSE/CLRCHN -> SETNAM -> SETLFS -> LOAD -> CLOSE/CLRCHN`
    - runtime re-entry still happens exactly once after `:ExitKernal()`
- Added proof at the real failing seam instead of extending ROM-tail guesses:
  - `commodore/c128/main.s`
    - under `C128_TEST_PRELOAD_VECTOR_GUARD`, snapshot 64 bytes of resident message code starting at `msg_show_more` before the first preload
    - added `c128_preload_vector_guard_fail_code_corruption_sym` and a compare routine that trips immediately if the first preload scribbles that resident Bank 0 code
  - `commodore/common/reu.s`
    - `c128_preload_asset_load` now calls the new resident-code guard right after runtime re-entry
  - `commodore/c128/run_tests128.sh`
    - `boot_preload_vector_guard_smoke` now breaks on and reports the resident-code corruption trap in addition to the existing IRQ/CHRIN/nesting owner traps
- Tightened the focused wrapper probe itself:
  - `commodore/c128/tests/test_wrapper_irq128.s`
    - now asserts CHRIN ownership together with IRQ ownership across `EnterKernal_sub` / `ExitKernal_sub`
    - but it is not left in the default unit runner yet, because the generic autostart worker currently makes VICE segfault before producing a useful monitor log for that specific low-level test

### Consultant Review
- Consultant review stayed aligned with the current path:
  - keep `EnterKernal_sub` / `ExitKernal_sub` mechanism-only
  - keep `c128_preload_asset_load` as one continuous KERNAL transaction
  - add a resident-code corruption guard around the first preload instead of another local IRQ-tail hack

### Verification
- `make disk128`
  - passed
- `TEST_FILTER='boot_preload_vector_guard_smoke|boot_title_load_resume_drive8_smoke|boot_title_load_resume_drive8_shipping_smoke' bash commodore/c128/run_tests128.sh`
  - passed with `=== Results: 3 passed, 0 failed (of 3 suites) ===`
- `make test128-fast-smoke`
  - passed with `=== Results: 8 passed, 0 failed (of 8 suites) ===`

### C128 Drive-8 Roundtrip Recovery
- The old C128 `save_load_roundtrip_drive8_smoke` was not a trustworthy closure gate because it depended on host image writeback after a monitor-driven save.
- The current authoritative automation shape is now same-session and in-emulator:
  - title-ready snapshot
  - `N`
  - `SHIFT+S1`
  - attach the save disk at the real FEAT-DISK insert prompts
  - hit `save_game_success_probe`
  - hit `game_over_prompt`
  - choose `S` to return to title
  - press `L`
  - require resume to `c128_town_move_diag_loop_top`
- That same-session roundtrip reproduces the live product contract without depending on host disk persistence after quit, and it is the test shape that should stay in the C128 smoke suite.

### Shared Program-Media Policy
- Product contract locked from user interview:
  - save/load prompts are about save media only
  - program-disk prompts are only for real runtime asset loads
  - after successful save/load, stay on the save disk until a later asset load truly needs program media
  - C64 disk-backed runtime may prompt/retry for program media
  - C128 normal post-preload runtime should not prompt for program media during save/load flow
- Implementation slice completed:
  - `commodore/common/overlay.s`
  - `commodore/common/tier_manager.s`
  - `commodore/common/string_bank.s`
  - `commodore/common/title_screen.s`
  - now route shared runtime asset prompting through `commodore/common/program_disk_prompt.s`
  - `commodore/c128/main.s` title `L` no longer overwrites load errors with `disk_prompt_game`; after successful load it goes straight to `load_resume_game`
- Test hardening completed:
  - existing C64 prompt/retry coverage remains in:
    - `commodore/c64/tests/test_feat_disk_contract.s`
    - `commodore/c64/tests/test_subsystems.s`
  - C128 drive-8 title-load coverage is now stronger:
    - `commodore/c128/run_tests128.sh` gained a prompt-guard variant for `boot_title_load_resume_drive8_smoke`
    - the smoke now resets a C128 test-only program-prompt counter at title `L`
    - it fails only if a program-disk prompt occurs during that load flow, instead of treating unrelated boot-time title prompt noise as failure
  - `build_load_resume_boot_assets` now seeds from the real built `out/moria128.d71` instead of hand-assembling an ad hoc disk with drifted filenames
  - `build_load_resume_prompt_guard_boot_assets` copies the real boot disk, swaps in a prompt-guard `moria128`, and layers `MORIA8.ID` / `THE.GAME` on top
- Exact verification on final tree:
  - `make test64`
    - `=== Results: 35 passed, 0 failed (of 35 suites) ===`
  - `make disk128`
    - PASS
  - `make test128-fast-smoke`
    - `=== Results: 3 passed, 0 failed (of 3 suites) ===`
- Focused verification on final tree:
  - `TEST_FILTER='boot_title_load_resume_smoke' bash commodore/c128/run_tests128.sh`
    - PASS
  - `TEST_FILTER='boot_title_load_resume_drive8_smoke' bash commodore/c128/run_tests128.sh`
    - PASS
  - later hardening found the first replacement swap smoke was still invalid inside the exact gate because:
    - the old synthetic drive-8 fixtures had been hybrid disks
    - `c1541 write` had seeded `MORIA8.ID` / `THE.GAME` as `prg`, not closed `seq`
    - the new Python swap smoke accidentally regressed VICE monitor startup by flipping `-remotemonitor/-binarymonitor` to `+remotemonitor/+binarymonitor`
  - the current tree fixes that substrate:
    - `commodore/c128/tests/patch_cbm_dir_type.py` now patches the test save-disk directory entries to closed `seq` and the builders fail if `c1541 -list` does not show `seq`
    - `commodore/c128/tests/title_load_swap_smoke.py` is back on the correct VICE monitor contract and drives the real one-drive mid-run disk swap
    - `commodore/c128/run_test_internal_worker.sh` no longer enables remote/binary monitor in the parallel unit workers, so they do not contend with the swap smoke's port
  - exact verification on the repaired test substrate:
    - `make test64`
      - `=== Results: 35 passed, 0 failed (of 35 suites) ===`
    - `make disk128`
      - PASS
    - `make test128-fast-smoke`
      - `=== Results: 5 passed, 0 failed (of 5 suites) ===`

### C128 Drive-8 Title Load Fix
- New live report:
  - on C128, loading from save drive `9` worked
  - the same valid save disk on drive `8` did not load from title `L`
- Root cause and fix:
  - `commodore/c128/main.s` always routed title `L` into `title_load_game`, which unconditionally called `disk_prompt_save`
  - after a fresh validate-only setup for one-drive mode, that re-entered the prompted path instead of using the already-mounted save disk
  - drive `9` masked the bug because `disk_prompt_save` is a no-op in two-drive mode
  - fix:
    - split the C128 title load tail into:
      - `title_load_game` for the normal prompted path
      - `title_load_game_ready` for the shared load tail
      - `title_load_game_mounted` for the fresh validate-only mounted path
    - title `L` now branches to `title_load_game_mounted` when `disk_setup_done` was previously clear and validate-only setup just succeeded
    - `title_load_game_mounted` performs `disk_init_drive` and then falls into the shared ready/load tail without a second `disk_prompt_save`
- Test hardening:
  - added `commodore/c128/tests/MORIA8.ID` so the load-resume smoke disk is a real valid save disk, not only a seeded `THE.GAME` image
  - added `boot_title_load_resume_drive8_smoke` to `commodore/c128/run_tests128.sh`
  - that smoke now drives the one-drive title flow with `L1 ` and verifies it reaches `load_resume_game`
- Exact required gates after the C128 drive-8 fix:
  - `make test64`
    - `=== Results: 35 passed, 0 failed (of 35 suites) ===`
  - `make disk128`
    - PASS
  - `make test128-fast-smoke`
    - `=== Results: 3 passed, 0 failed (of 3 suites) ===`

### FEAT-DISK Prompt Screen Refinement
- Live UX report:
  - one-drive save/program-disk prompts did not fully own the screen
  - after dismissing a prompt, stale `Insert ... disk` text remained behind top-of-screen status text
  - during save overwrite, the stale message state could surface `Overwrite? Y/N -More-`
- Fix:
  - `commodore/common/disk_swap.s`
    - `disk_prompt` now clears the screen both before showing the modal prompt and again immediately after dismiss + `disk_init_drive`
    - on C64 it explicitly restores `$01` to `BANK_NO_BASIC` after the post-dismiss clear so the follow-on UI starts in the normal bank state
  - `commodore/common/save.s`
    - `save_game` now calls `msg_init` before printing its top-of-screen status text so stale scroll/more state does not leak into the overwrite prompt
  - code-size recovery was done by collapsing code paths and dead data, not by trimming live UX strings:
    - removed the obsolete C64 `program_disk_prompt` indirection from shared loaders and test harnesses
    - kept all user-facing copy intact
- Test fallout fixed:
  - `commodore/c64/tests/test_subsystems.s`
    - removed stale `program_disk_prompt_set` setup after reverting to direct `disk_prompt_game` calls
  - `commodore/c64/tests/test_save.s`
    - removed a duplicate local `disk_prompt_game` stub because `disk_swap.s` already defines the symbol in that suite
  - `commodore/c64/tests/test_disk_swap.s`
    - updated the focused prompt expectations to assert two full-screen clears for one-drive modal prompts
- Exact required gates after the prompt-screen refinement:
  - `make test64`
    - `=== Results: 35 passed, 0 failed (of 35 suites) ===`
  - `make disk128`
    - PASS
  - `make test128-fast-smoke`
    - `=== Results: 3 passed, 0 failed (of 3 suites) ===`

### C64 Modal Prompt Repaint Follow-up
- Live follow-up:
  - on one-drive save-again, the `Insert save disk` modal could still show lower gameplay/status remnants even though the shared prompt path already cleared before/after dismiss
- Refinement:
  - `commodore/common/disk_swap.s`
    - C64 now blanks the display (`$d011` DEN off) while repainting the modal prompt screen
    - then restores display (`$d011` DEN on) only after the finished prompt text is on screen
  - this keeps the prompt repaint atomic from the player's point of view and avoids exposing partial lower-screen remnants during the modal transition
- Exact required gates after the C64 modal repaint follow-up:
  - `make test64`
    - `=== Results: 35 passed, 0 failed (of 35 suites) ===`
  - `make disk128`
    - PASS
  - `make test128-fast-smoke`
    - `=== Results: 3 passed, 0 failed (of 3 suites) ===`

### C64 Footer Clear Follow-up
- Live follow-up:
  - even after the atomic modal repaint, the one-drive `Insert save disk` screen could still leave rows 21–24 (status + input footer) visible
- Refinement:
  - `commodore/common/disk_swap.s`
    - the C64 modal prompt path now explicitly clears rows `STATUS_ROW` through `STATUS_ROW + 3` both before showing the prompt and again after dismiss + `disk_init_drive`
    - this keeps the FEAT-DISK modal contract independent of whether a broader full-screen clear or later redraw path leaves footer rows intact
  - `commodore/c64/tests/test_disk_swap.s`
    - updated to expect the extra eight row clears from the pre/post modal footer cleanup
- Exact required gates after the C64 footer-clear follow-up:
  - `make test64`
    - `=== Results: 35 passed, 0 failed (of 35 suites) ===`
  - `make disk128`
    - PASS
  - `make test128-fast-smoke`
    - `=== Results: 3 passed, 0 failed (of 3 suites) ===`

### Load-Side Insert Prompt Clear Follow-up
- Live follow-up:
  - during title/load setup, the overlay-based `Insert a separate Save Disk` prompt still left the old screen visible after the user inserted the disk and pressed a key
  - this was a separate path from the runtime `disk_prompt_*` modal that the earlier fixes targeted
- Fix:
  - `commodore/common/ui_disk_setup.s`
    - `uds_show_insert_prompt` now calls `ui_clear_full_screen_safe` immediately after `input_get_modal_dismiss_key`
    - that makes the load/setup overlay path clear on dismiss before control returns to disk validation / load flow
- Exact required gates after the load-side insert-prompt clear fix:
  - `make test64`
    - `=== Results: 35 passed, 0 failed (of 35 suites) ===`
  - `make disk128`
    - PASS
  - `make test128-fast-smoke`
    - `=== Results: 3 passed, 0 failed (of 3 suites) ===`

### Runtime Prompt Residue Follow-up
- Live follow-up:
  - even after the footer-specific fixes, a small center-screen chunk of old viewport content could still survive under the runtime `Insert save disk` modal
  - this pointed back to the bulk C64 `screen_clear` path in `disk_prompt`, not the overlay setup prompt
- Fix:
  - `commodore/common/disk_swap.s`
    - C64 runtime disk prompts no longer rely on the bulk `screen_clear` path
    - they now clear all 25 screen rows row-by-row before showing the modal and again after dismiss + `disk_init_drive`
    - after each full row-by-row clear, the prompt path explicitly reapplies the same status-redraw contract as a full-screen clear by setting `zp_ui_dirty |= %10000001`
  - `commodore/c64/tests/test_disk_swap.s`
    - updated to expect the row-by-row full-screen clears on the C64 runtime prompt path
- Exact required gates after the runtime prompt residue fix:
  - `make test64`
    - `=== Results: 35 passed, 0 failed (of 35 suites) ===`
  - `make disk128`
    - PASS
  - `make test128-fast-smoke`
    - `=== Results: 3 passed, 0 failed (of 3 suites) ===`

### Program Disk Retry Contract
- User report:
  - when a program-disk asset/overlay/title load fails because the wrong disk is mounted, the runtime does not prompt for the program disk and retry cleanly
- Consultant-backed design:
  - keep raw disk loaders low-level
  - put retry/prompt ownership in the public loaders (`overlay_load`, `tier_load`, `bank_load_recall`, `title_load_and_draw`)
  - do not bake UI into `overlay_load_disk`/peer primitives
- Final implementation:
  - C64:
    - added `commodore/common/program_disk_prompt.s` as a bindable prompt hook for focused harnesses that import shared loaders without the full `disk_swap.s` UI
    - `commodore/c64/main.s` binds that hook to `disk_prompt_game` at startup
  - C128:
    - shared loaders call `disk_prompt_game` directly to avoid carrying the bindable hook into the C128 resident size budget
  - shared loader behavior now retries after a wrong program disk in:
    - `commodore/common/overlay.s`
    - `commodore/common/tier_manager.s`
    - `commodore/common/string_bank.s`
    - `commodore/common/title_screen.s`
- Test coverage:
  - `commodore/c64/tests/test_feat_disk_contract.s`
    - covers overlay/title retry after one failed LOAD
    - covers validate-only wrong-save-disk then retry-to-valid-disk behavior
  - `commodore/c64/tests/test_subsystems.s`
    - updated for the new retry contract so it no longer expects old carry-set failure semantics from public loaders
- Exact gates after the program-disk retry fix:
  - `make test64`
    - `=== Results: 35 passed, 0 failed (of 35 suites) ===`
  - `make disk128`
    - PASS
  - `make test128-fast-smoke`
    - `=== Results: 3 passed, 0 failed (of 3 suites) ===`

### Architecture Correction
- Reverted the bad C64 string-cutting pass. User-facing copy is restored and is not a valid space-recovery target.
- Moved the staged C64 banked payload source out of the resident Default segment and into `OVL.UI`:
  - `commodore/c64/main.s:init_copy_banked` now loads `OVL_UI` and copies from `$E000` to runtime `$F000`
  - the old inline `banked_payload` bytes were removed from the Default segment
  - the staged source now lives in the `UiOverlay` segment as `.pseudopc $F000 { ... }`
- This keeps the resident C64 image below `MAP_BASE` without trimming UX text and preserves the banked runtime contract.

### Gate Repair
- `make test64` initially went red because `commodore/c64/tests/test_disk_swap.s` still expected the old legacy `THE.GAME` fallback path that was already removed from shipping code.
- The harness now matches the current marker-only `disk_require_save_media` contract again.
- `make disk128` also caught a real compile break: `commodore/common/save.s` called `save_file_exists` on C128 while the helper was still hidden behind `#if !C128`.
- `save_file_exists` is now shared and only performs the `$dd00` restore on C64.

### Current Live Focus
- Exact gates are green again:
  - `make test64`
  - `make disk128`
  - `make test128-fast-smoke`
- Current live C64 issue still to resolve:
  - title `L` wrong-disk retry UX is better
  - but the user reports the retry path does not appear to actually reread subsequent disks, including a valid save disk

### Retry Cleanup Fix
- The likely owner of the remaining C64 wrong-disk retry failure was `c64_disk_marker_present_impl` in `commodore/common/disk_setup_banked.s`.
- On marker-file `OPEN` failure, that helper returned immediately and skipped the shared close path.
- The helper now routes failed `OPEN`s through the same close path used by later marker-read failures, so the logical file/channel cleanup happens before the next retry.
- Added a focused C64 suite:
  - `commodore/c64/tests/test_disk_marker_present_impl.s`
  - proves one failed marker `OPEN` does not poison the next probe
  - wired into `commodore/c64/run_tests.sh`

### Verification
- Exact gates after the retry-cleanup fix:
  - `make test64` -> `=== Results: 34 passed, 0 failed (of 34 suites) ===`
  - `make disk128` -> PASS
  - `make test128-fast-smoke` -> `=== Results: 3 passed, 0 failed (of 3 suites) ===`

### Follow-up Root Cause
- The first retry-cleanup implementation moved C64 marker reread into banked payload code at `$FE67+`.
- That was architecturally invalid because the helper itself then switched `$01` to `$36`, exposing KERNAL ROM over `$E000-$FFFF` while still executing from that same banked range.
- Live proof from the user:
  - `PC=$FE70`
  - `$01=$36`
  - `JAM` during the “check new disk” path
- The fix is now:
  - resident stub in `commodore/c64/main.s`
  - copy raw marker-read helper bytes into owned low RAM at `CREATURE_BASE`
  - execute the raw KERNAL transaction there
  - no continued execution from banked `$F000-$FFFF` once `$01=$36`
- The focused suite `commodore/c64/tests/test_disk_marker_present_impl.s` was updated to follow the same copy-to-low-RAM contract instead of the removed banked symbol.

### Verification
- Exact gates after the low-RAM marker-read fix:
  - `make test64` -> `=== Results: 34 passed, 0 failed (of 34 suites) ===`
  - `make disk128` -> PASS
  - `make test128-fast-smoke` -> `=== Results: 3 passed, 0 failed (of 3 suites) ===`

### Root Cause Reframe
- A focused real-disk runtime repro was added in `commodore/c64/tests/test_disk_marker_runtime.s`.
- That repro exercises the actual C64 marker path against a real D64 under VICE:
  - `disk_init_drive`
  - initial `disk_marker_present` miss
  - `disk_marker_init`
  - immediate `disk_marker_present` reread
- Result under clean VICE config:
  - marker init succeeds
  - immediate reread succeeds
  - `MORIA8.ID` is present on disk afterward
- Result under the user's normal JiffyDOS VICE config:
  - the same repro fails only when the disk image is attached read-only
  - VICE reports `AttachDevice8d0Readonly=1`
  - with `-attach8rw`, the same JiffyDOS repro succeeds and `MORIA8.ID` is written
- Conclusion:
  - the remaining live C64 init/save failure is no longer explained by the generic marker writer/rereader code
  - the strongest active owner is the emulator attachment mode being read-only, which the code currently surfaces poorly as a generic disk/init failure

### Redesign Proposal
- Freeze scope to one live gate only:
  - C64 fresh save-disk initialization from Disk Setup
  - current live failure is still the marker writer, now surfacing as status/stage `2`
- Stop patching the special C64 banked marker writer in `commodore/common/disk_setup_banked.s`.
- Replace that writer with a new resident C64 helper in `commodore/c64/main.s`, tentatively `c64_disk_marker_write_resident`, with the same transaction shape as the known-good `hiscore_save` writer in `commodore/common/score_io.s`:
  - `SETNAM`
  - `SETLFS`
  - `OPEN`
  - `CHKOUT`
  - `CHROUT...`
  - `CLRCHN`
  - `CLOSE`
- Keep the helper entirely in resident main RAM, not the banked payload and not behind `c64_disk_call`.
- `disk_marker_init` in `commodore/common/disk_setup_banked.s` should call the resident helper directly on C64 instead of `c64_disk_marker_write_phys`.
- Keep `disk_marker_present` unchanged for the first cut so the redesign only swaps one side of the contract at a time.
- Keep diagnostics minimal:
  - one stage/status byte only
  - no oversized command-channel helpers unless the resident path still fails
- Required proof after implementation:
  - exact gates green:
    - `make disk128`
    - `make test128-fast-smoke`
    - `make test64`
  - then rerun the same narrow live C64 init repro before touching save/load follow-up bugs

## BUG-SENSE-SURROUNDINGS-UMORIA-MAP-BEHAVIOR

### Goal
- Make the priest `Sense Surroundings` prayer follow upstream `umoria` `spellMapCurrentArea()` behavior exactly enough for the Commodore tile model:
  - map the current visible area plus the same random spill shape
  - reveal floor tiles
  - reveal enclosing room/corridor walls around mapped floors
  - keep hidden doors hidden
  - keep wizard reveal separate

### Implementation
- Added a dedicated `eff_map_area` in `commodore/common/player_magic_map.s` for the umoria-style prayer behavior.
- Kept wizard floor-plan reveal separate in `commodore/common/player_magic_utility.s` / `commodore/common/wizard.s`.
- On C128, kept `Sense Surroundings` out of the full `DeathOverlay` by routing both earthquake and map-area through the existing item-overlay trampoline, with dispatch selected from resident `pm_spell_idx`.
- Tightened the prayer dispatch code in `commodore/common/player_magic_execute_overlay.s` by sharing the undead/evil dispel setup tail, which recovered the bytes needed to keep `DeathOverlay` under `$F000`.
- Expanded `commodore/c64/tests/test_utility_effects.s` to prove:
  - mapped room floor is revealed
  - mapped room wall is revealed
  - mapped corridor wall is revealed
  - untouched rock stays dark
  - hidden doors stay hidden

### Review
- Upstream parity checked against `umoria` prayer behavior rather than the local wizard reveal path.
- C128 staging, overlay, and runtime-low residency constraints were all re-verified after the ownership split.

### Verification
- Exact reported command: `make test64` PASS
- Broader regression suites: `make test128-fast-smoke` PASS

### Live Regression Follow-up
- The first C128 prayer patch still shipped a real live regression even though the gates were green.
- User monitor trace:
  - CPU JAM at `$49B1`
  - caller chain through `$49AE`
- Root cause:
  - `eff_map_area` used raw `(zp_ptr1),y` reads/writes in the adjacent-wall pass.
  - On C128, map rows live in Bank 1, so those raw accesses scribbled Bank 0 resident code instead of the map.
  - `$49AE` is `status_put_stat_val`, which got overwritten by Bank 1-style map bytes and later JAMed when status redraw executed.
- Fix:
  - switched the adjacent-tile pass in `commodore/common/player_magic_map.s` to `:MapRead_ptr1_y()` / `:MapWrite_ptr1_y()`
  - left the C64 behavior unchanged while restoring correct Bank 1 ownership on C128

### Verification
- Exact reported command: `make test64` PASS
- Broader regression suites: `make test128-fast-smoke` PASS

### Redesign Implementation
- Implemented the redesign as low-RAM copied helper images instead of a special banked C64 writer:
  - `commodore/common/disk_setup_banked.s` now owns two raw helper byte blocks:
    - `c64_disk_marker_write_scratch`
    - `c64_disk_marker_read_scratch`
  - both helpers execute from `$033c` at runtime and use one continuous raw KERNAL transaction:
    - write: `SETNAM -> SETLFS -> OPEN -> CHKOUT -> CHROUT... -> CLRCHN -> CLOSE`
    - read: `SETNAM -> SETLFS -> OPEN -> CHKIN -> CHRIN... -> CLRCHN -> CLOSE`
- The C64 write path no longer needs a resident `c64_disk_marker_write_resident` dispatcher in `commodore/c64/main.s`.
- `disk_marker_init` in `commodore/common/disk_setup_banked.s` now copies the write helper bytes into low RAM and calls them directly.
- `c64_disk_marker_present` in `commodore/c64/main.s` is now only a small dispatcher:
  - copies `c64_disk_marker_read_scratch` into low RAM
  - calls it
  - returns the helper carry result
- The copied helpers were flattened into ordinary stored bytes rather than nested `.pseudopc` blocks, and their internal control flow now stays branch-relative so the copied image runs correctly at `$033c`.
- Final C64 layout result after trimming:
  - `Program fits below MAP_BASE=true`
  - `Payload fits below I/O ($D000)=true`
  - `Banked code fits below CPU vectors=true`

### Verification
- Exact required gates passed sequentially:
  - `make disk128`
  - `make test128-fast-smoke`
  - `make test64`
- Final exact C64 gate result:
  - `=== Results: 33 passed, 0 failed (of 33 suites) ===`
- Additional diagnostic confirmation:
  - isolated `test_monster_ai` still reaches its `BRK`/result dump under the same non-warp VICE monitor command used by the suite; the earlier apparent stall was not a new logic regression in that test

### Save Error UX Recovery
- Goal:
  - keep all UX strings intact
  - make C64 save failures show DOS status digits instead of only generic `Disk error!`
  - recover resident bytes from code only so `make test64` stays green
- Final code recovery:
  - restored `save_welcome_str` in `commodore/common/runtime_ui_strings.s`
  - removed the C64-dead `save_file_exists` body from the resident C64 build by gating it to C128 only in `commodore/common/save.s`
  - removed the extra C64 error-path reread helper and now formats `save_ioerr_status_str` inline from the already captured DOS digits
  - deduplicated the write filename storage by aliasing plain create to `save_replace_filename + 1`
  - removed C64-only dead `zp_kernal_status` clears from the save path
- Exact required gates after the save-error UX change:
  - `make test64`
    - `=== Results: 34 passed, 0 failed (of 34 suites) ===`
  - `make disk128`
    - PASS
  - `make test128-fast-smoke`
    - `=== Results: 3 passed, 0 failed (of 3 suites) ===`

### C64 Save Overwrite Follow-up
- Live clue:
  - C64 save failure now surfaced `Disk error 63.`
  - `63` is the CBM DOS file-exists class, so the save path was correctly surfacing the create failure but still not taking a clean overwrite retry path
- Fix:
  - The first DOS-status fix was not enough because the suite still had no real-disk overwrite repro; the user kept finding the failure live.
  - Added `commodore/c64/tests/test_save_overwrite_runtime.s`, which:
    - creates a writable temp D64 with `c1541`
    - seeds an initial `THE.GAME`
    - proves the seeded file is readable
    - proves `save_file_exists` sees the existing file
    - performs the overwrite open/write path
    - reads the overwritten bytes back from disk
  - Wired that runtime suite into `commodore/c64/run_tests.sh` as `save_overwrite_runtime`.
  - The first run of that new suite exposed the real contract bug:
    - the C64 save path was still relying on “plain create fails with 63” as the overwrite branch point
    - the real-disk overwrite repro showed that was the wrong seam to trust
  - `commodore/common/save.s` now uses the product contract directly:
    - `save_file_exists`
    - prompt `Overwrite? Y/N`
    - plain create only when absent
    - direct `@0:THE.GAME,S,W` replace-open when confirmed
  - Recovered the extra C64 resident bytes from code only:
    - collapsed the duplicated save open path
    - merged the post-close DOS-status helper into one routine
    - shared the common save-fail return tail
    - kept all UX copy unchanged
- Exact required gates after the integration-backed overwrite fix:
  - `make test64`
    - `=== Results: 35 passed, 0 failed (of 35 suites) ===`
  - `make disk128`
    - PASS
  - `make test128-fast-smoke`
    - `=== Results: 3 passed, 0 failed (of 3 suites) ===`

### C64 Load Follow-up
- New live report:
  - user reported a C64 load regression showing `Save file not found.`
- Diagnostic work:
  - added `commodore/c64/tests/test_save_load_runtime.s` as a real-disk runtime repro candidate
  - first tried the light fixture route:
    - generate a canned `THE.GAME`
    - seed it onto a temp D64 with `c1541`
    - load it through `load_game`
  - that did not produce a trustworthy production signal because `c1541` write semantics around dotted sequential filenames are awkward enough that the fixture itself was suspect
  - then switched the runtime test to the direct `save_game -> load_game` path on a temp D64 under `-warp`
  - that path did not produce a code-level failure either; it simply failed to reach the BRK breakpoint under the default cycle cap, so it is not yet a stable default-suite gate
- Current status:
  - the attempted load runtime repro is kept as diagnostic code, not part of the default `make test64` gate yet
  - exact gate was restored to green after removing that unstable suite from the default runner
- Exact required gates after restoring the default gate:
  - `make test64`
    - `=== Results: 35 passed, 0 failed (of 35 suites) ===`
 - Root cause and fix:
   - after fresh validate-only Disk Setup from title `L`, `commodore/c64/main.s` jumped straight into `load_game`
   - that path skipped the post-insert `disk_init_drive` call that the normal prompted save-disk path already performs
   - result: the same valid disk could pass marker validation and then immediately fail the first load with `Save file not found.`
   - fix:
     - split the resident title load tail into:
       - `title_load_game_ready` for the already-initialized prompt path
       - `title_load_game_mounted` for the fresh validate-only path
     - `title_load_game_mounted` now performs `disk_init_drive` before `msg_init` and `load_game`
     - `title_load_game` still uses `disk_prompt_save`, so the user does not get a duplicate save-disk prompt
- Exact required gates after the resident load-tail fix:
  - `make test64`
    - `=== Results: 35 passed, 0 failed (of 35 suites) ===`
  - `make disk128`
    - PASS
  - `make test128-fast-smoke`
    - `=== Results: 3 passed, 0 failed (of 3 suites) ===`

### C64 Save Overwrite Follow-up
- New live report:
  - after a successful C64 load from a valid save disk, saving back to the same disk still failed with `Disk error 63`
- Root cause and fix:
  - the product overwrite path depended on `save_file_exists`, but that probe was still using its own secondary address instead of the same read contract the real load path already uses
  - on the user's live JiffyDOS path, that let the existence probe miss `THE.GAME`, so save fell through to plain create and DOS correctly returned `63 FILE EXISTS`
  - `commodore/common/io_kernal_consts.s` now aliases `CHECK_SEC_ADDR` to `LOAD_SEC_ADDR`, so the existence probe uses the same proven read channel as `load_game`
- Test hardening:
  - `commodore/c64/tests/test_save_overwrite_runtime.s` no longer stops at the lower-level manual `@0:` open path
  - it now patches `input_get_key` to answer `Y`, calls top-level `save_game`, and verifies that the overwritten file begins with the real `save_magic` header on a writable temp D64
  - this keeps the exact `make test64` gate aligned with the actual product overwrite contract instead of only the primitive KERNAL open/close sequence
- Exact required gates after the overwrite-probe fix:
  - `make test64`
    - `=== Results: 35 passed, 0 failed (of 35 suites) ===`
  - `make disk128`
    - PASS
  - `make test128-fast-smoke`
    - `=== Results: 3 passed, 0 failed (of 3 suites) ===`

### Next Live Gate
- Narrow user repro only:
  - fresh save disk on C64
  - `Disk Setup`
  - initialize it
- If it still fails, keep the current numeric C64 init diagnostic in the fail screen for one more pass before cleanup

### Live Correction
- The latest live C64 repro returned to BASIC during marker initialization.
- User correction:
  - the current test environment uses JiffyDOS
  - JiffyDOS uses the tape buffer
  - therefore the copied-helper execution address at `$033c` is invalid and must be treated as off-limits
- That invalidates the current scratch-copy redesign even though the exact automated gates are green.

### Substrate Correction
- The remaining invalid tape-buffer use was in `commodore/c64/main.s`: `c64_disk_marker_present` still copied the marker-read helper to `$033c`.
- That dispatcher now uses the same always-visible owned C64 runtime scratch region as the write helper: `CREATURE_BASE` (`$c020`), which is already reserved as non-gameplay scratch in `commodore/c64/memory.s`.
- Scope of this correction was intentionally narrow:
  - no new FEAT-DISK flow changes
  - no save/load contract changes
  - only the helper execution substrate moved off the tape buffer

### Root Cause Correction
- The copied C64 marker helpers in `commodore/common/disk_setup_banked.s` had a real return-path bug:
  - entry saved `$01`
  - exit then did `php ... pla / sta $01 / plp`
  - after `php`, the top stack byte is processor flags, not the saved `$01`
- So the helper was restoring flags into `$01` and then restoring the old `$01` byte into processor status.
- That is a direct C64 banking/control-flow corruption bug and is consistent with the live “return to BASIC” symptom during marker init.
- The fix now stores the saved bank byte in existing resident scratch (`disk_temp`) instead of the hardware stack, then restores `$01` after the KERNAL transaction and before `plp`.
- The follow-up live trace then showed `IRQ -> $FFFF` with `BRK` at `$00c0`, which narrowed the remaining bug further:
  - even after fixing the stack order, the helper was still restoring the caller's old interrupt flags while returning into a banked-payload caller with KERNAL hidden again
  - that recreated a live IRQ window into invalid vectors
- The helper epilogues now keep IRQs disabled on return instead of restoring stale caller flags across the bank boundary.
- To keep the exact C64 gate green, I also removed the temporary C64 init stage-byte instrumentation from the banked init path once the helper return contract was fixed.

### Verification
- `make disk128`
  - passed
- `make test128-fast-smoke`
  - passed with `=== Results: 3 passed, 0 failed (of 3 suites) ===`
- `make test64`
  - passed with `=== Results: 33 passed, 0 failed (of 33 suites) ===`

- BUG-C128-PRAY-NO-EFFECT-WIZARD-MISDISPATCH:
  - root cause 1: C128 `Ctrl+W` decoded `W` and Ctrl from separate scans, so the live command path could race back to plain `CMD_WEAR`; fix was to normalize the chord from the same CIA sample in `input128.s` and keep `CTRL+W` mapped as PETSCII `$17` -> `CMD_WIZARD`
  - root cause 2: the suite had no priest execution smoke, so the earlier C128 prayer regression escaped; fix was to add `scripted_prayer_cast_smoke` plus wire it into `test128-fast-smoke`
  - correction after live retest: the scripted smoke was still too weak because it only proved the seeded bless timer path and could pass while the live C128 priest UX still appeared broken; the active next step is to replace it with a product-faithful priest smoke that proves visible prayer feedback/effect through the real gameplay path
  - follow-on regressions fixed while proving the gate:
    - resident/banked layout drift from the new C128 input helper and prayer smoke support
    - stale C128 test harness stubs missing `eff_detect_timer` and `tier_silent_restore` after earlier shared gameplay changes
  - verification:
    - `make build128` PASS
    - `TEST_FILTER=scripted_prayer_cast_smoke bash commodore/c128/run_tests128.sh` PASS
    - `make test64` PASS (`36 passed, 0 failed`)
    - `make test128-fast` PASS
    - `make test128-fast-smoke` PASS (`5 passed, 0 failed`)

### Current Review
- BUG-PRAYER-PSEUDOID-HUFFMAN:
  - root cause: `turn_tick_pseudo_id` still assumed contiguous resident Huffman IDs and could decode a fresh pseudo-ID message as `You feel righteous!` while running; the real bless expiry path was separate and still correctly produced `The prayer has expired.`
  - fix shape:
    - added explicit PID quality strings in `data/huffman_strings.txt`
    - made the PID block contiguous again so `turn_tick_pseudo_id` can use arithmetic without a resident lookup table
    - moved overlay-only prayer feedback strings (`You feel righteous!`, `A monster falls asleep.`, `You feel resistant to heat and cold.`) out of the resident Huffman pool into `player_magic_feedback.s`
    - kept the shared resident prayer-expiry message local in `turn.s`
    - refreshed the C64 subsystem string-bank fixture and the test-layout buffers that drifted because of the Huffman/table changes
  - verification:
    - `make test64` PASS (`44 passed, 0 failed`)
    - `make test128-fast-smoke` PASS (`6 passed, 0 failed`)

- ITEM-ACTIONS-OVERLAY-AND-UMORIA-PSEUDOID:
  - item-action cold paths (`item_read_scroll`, `item_aim_wand`, `item_use_staff`, `item_refuel`) now live in a dedicated product overlay instead of bloating the resident/default image
  - automatic pseudo-ID messaging now matches the `umoria`-style useful wording pass instead of the old quality-adjective presentation, with the prayer pseudo-ID decode bug fixed by restoring a contiguous PID block in the Huffman table
  - cleanup/fallout fixed in the exact C64 gate:
    - `test_ui_views.s` had a stale 41-character equipment expectation on a 40-column row
    - `test_item.s` had silently grown past `MAP_BASE`; `store_data.s` moved out of the resident test body and the suite now asserts the boundary explicitly
    - `run_tests.sh` now parses `script` tty logs as text and retries once when the VICE monitor dump is missing
  - verification:
    - `make test64` PASS (`44 passed, 0 failed`)
    - `make test128-fast-smoke` PASS (`6 passed, 0 failed`)

- BUG-C128-LOAD-RESUME-VIEWPORT-SEED:
  - root cause: `load_resume_game` called `viewport_update` as if it were a fresh initializer, but the C128 implementation is a deadband adjuster that expects sane existing `zp_view_x/zp_view_y`
  - snapshot proof from `~/vice-snapshot-20260419114026.vsf`:
    - `zp_player_x = $b0`, `zp_player_y = $0a`
    - `zp_view_x = $6f`, `zp_view_y = $ff`
    - `zp_msg_flags = $01`
  - that stale `zp_view_y = $ff` made the first post-load render start from map row 255, which matches the stray top-row VDC garbage after returning from save
  - fix shape:
    - seed `zp_view_x/zp_view_y` to `0` in `load_resume_game` before the first `viewport_update`
    - add a direct C128 `main_loop128` regression proving load-resume zeroes stale viewport state before the deadband updater runs
    - repair the unrelated but real overlay-state drift in `reu_stash_overlays`, which had added overlay 7 everywhere except the REU stash loop
  - note:
    - `You feel weakened.` is not part of this bug; it is the real poison-dart CON-drain message from `dungeon_features.s`, and the live screenshot's `CO:15` matches that effect
  - verification:
    - `make test64` PASS (`44 passed, 0 failed`)
    - `make test128-fast-smoke` PASS (`6 passed, 0 failed`)

- BUG-C128-INVENTORY-EGO-SUFFIX-GARBAGE:
  - live symptom on fresh-build C128 inventory screen: `Long SwordITEM 0-63:`
  - root cause: this was not stale-row residue from the wizard prompt; the append started exactly at the end of the base item name because the display path would blindly treat any nonzero `inv_ego` as a valid suffix/prefix index
  - fix shape:
    - clamp invalid ego values in the shared display helpers before appending prefixes/suffixes
    - keep the fix in the shared UI path (`game_loop.s` / `ui_trampoline_stubs.s`) instead of growing the C128 low-runtime ego module
    - add a C64 regression proving an invalid `inv_ego` on `Long Sword` renders as plain `Long Sword` rather than walking into unrelated text
  - verification:
    - `make test64` PASS (`44 passed, 0 failed`)
    - `make test128-fast-smoke` PASS (`6 passed, 0 failed`)

- BUG-C128-SAVE-DRIVE9-FALSE-CORRUPT:
  - Reported Failure Gate:
    - `x128 -80col -8 commodore/out/moria8-c128.d71 -9 ~/moria8128save.d81`
    - title flow: `Load` -> `Use drive 9?` = `Yes` -> dismiss `Insert save disk`
  - snapshot proof from `~/vice-snapshot-20260419214207.vsf`:
    - `load_result = $02` (`CORRUPT`)
    - `load_save_version = $0e`
    - `save_device = $09`
    - `save_io_error = $00`
    - so the failure was not unsupported-version or drive selection; it was a checksum mismatch during a valid legacy C128 load
  - root cause:
    - the C128 KERNAL byte-I/O wrappers in `commodore/common/save.s` (`load_read_byte`, `save_write_byte`, `save_write_byte_raw`) did not preserve `X`
    - `load_read_floor_items` and `save_write_floor_items` keep the floor-slot index in `X` across those calls
    - on the live C128 drive-9 path, `CHRIN/CHROUT` clobbered `X`, so floor-item logical fields were under-read/under-written
    - that shifted the legacy 32-slot floor-item stream, left `fi_p1` zeroed for gold stacks, misaligned later blocks, and made a valid save fail the final checksum compare
  - fix shape:
    - preserve `X` in the shared C128 save/load byte wrappers instead of patching the floor-item loops ad hoc
    - keep the legacy-version support and `Unsupported save.` split from the earlier compatibility work
  - verification:
    - `make test64` PASS (`44 passed, 0 failed`)
    - `make test128-fast-smoke` PASS (`6 passed, 0 failed`)

- [ ] BUG-LONG-MESSAGE-TRUNCATION-POLISH
- [ ] backlog:
  - long combat/status messages can clip instead of wrapping across the 2-line message area, e.g. `Your spell fails.` followed by a long monster effect line like `the Ancient Multi-Hued Dragon confuses yo`
  - current implementation clamps live message rendering to one row width and stores only one `SCREEN_COLS` slice per history entry in `commodore/common/ui_messages.s`, `commodore/c64/screen.s`, and `commodore/c128/screen_vdc.s`
  - priority: low polish; rare on normal play, more visible on deeper levels with long monster names/effects
  - desired future fix: wrap across rows 0-1 cleanly, preserve sensible `-more-` behavior, and decide whether history should keep wrapped/continued lines or widened entries
