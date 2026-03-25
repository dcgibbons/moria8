# Lessons Learned

## 2026-03-24 — Escalate as soon as the memory map proves a feature does not fit

- **Issue:** I kept trying to optimize the oversized `look` rewrite locally instead of surfacing the memory-map failure as soon as the build proved it.
- **Root Cause:** I stayed in fix-it-first mode and treated the overage as something to clean up before reporting, even after the C64 main image had already crossed `MAP_BASE`.
- **Resolution:** When a feature trips a hard segment boundary, state the exact addresses and overage immediately and get direction before doing more speculative cleanup.
- **Rule:** **If the memory map or `.assert` output shows a feature no longer fits, stop spinning and escalate with the exact segment addresses before doing more local optimization.**

## 2026-03-24 — Split Umoria-only behavior from VMS baseline before porting a large gameplay feature

- **Issue:** I treated `look` as if only the all-directions `5` mode differed between Umoria and VMS-Moria, then built a large interactive cone/recall implementation around that assumption.
- **Root Cause:** I checked one visible feature delta, but I did not finish the side-by-side comparison of the whole command contract before writing the port. Local VMS-Moria's `look` is much smaller than Umoria's: straight-ray, non-interactive, and no recall handoff.
- **Resolution:** Re-anchor the task on the local primary sources and separate the shared baseline from Umoria-only enhancements before committing to an implementation shape.
- **Rule:** **When porting a large gameplay/UI command, compare the full local Umoria and VMS-Moria implementations first. Lock the shared baseline separately from Umoria-only enhancements before spending memory budget on the richer path.**

## 2026-03-24 — Check the known local third-party source tree before reaching for network access

- **Issue:** I started to request a network fetch of upstream Umoria even though this workspace already has a local upstream checkout at `~/Projects/thirdparty/umoria`.
- **Root Cause:** I anchored on the earlier web/manual lookup and did not verify whether the repo's known local third-party mirror was already available before escalating.
- **Resolution:** For source-parity work against upstream projects, check the existing local third-party trees first and treat them as the primary source when present.
- **Rule:** **Before requesting network access for upstream source code, search the local `~/Projects/thirdparty/` mirrors and any project-documented vendor paths.**

## 2026-03-24 — Full-screen clears must invalidate the status cache

- **Issue:** On C64, returning from the character sheet left the status rows blank until a later gameplay update happened to redraw them.
- **Root Cause:** `screen_clear` wiped the status rows, but `status_draw` saw unchanged cached values and skipped repainting because no force-redraw flag was set.
- **Resolution:** Any full-screen clear that can erase the status area must set the status force-redraw bit so the next `status_draw` repaints even when player values are unchanged.
- **Rule:** **When a UI path uses `screen_clear` and then returns to gameplay, invalidate or force the status redraw explicitly. Do not rely on cached-value changes to redraw erased rows.**

## VDC Hardware Fill (C128)

- **Issue:** Using VDC hardware fill (Reg 30) for `screen_clear` and `screen_clear_row` caused a fatal CPU crash (JAM) during character creation (after pressing 'N' on the title screen).
- **Symptom:** CPU jumps to an invalid address (e.g., $A94E) and executes an operand as an opcode.
- **Root Cause:** Likely a timing or race condition between the VDC's internal hardware fill operation and the CPU's subsequent register access, or an interaction with the KERNAL's interrupt-driven VDC access (even with `sei`). VDC hardware fill takes several milliseconds; if not polled correctly or if a register is selected mid-operation, the VDC status or data register state can become corrupted.
- **Resolution:** Revert to streaming loops for block clears. While slower, streaming with `vdc_wait` per byte is deterministic and avoids the complexity of managing the VDC's internal state during autonomous hardware operations.
- **Rule:** **Prefer streaming loops over hardware fill (Reg 30)** for block operations unless the performance gain is absolutely critical and the busy-state management is exhaustively verified.

## Overlays and Banked Payload Overlap (C128)

- **Issue:** A CPU JAM (crash) at $76CB (inside `item_get_name_ptr`) occurred when entering the dungeon from town.
- **Root Cause:** The `DungeonGenOverlay` (loaded at $E000-$EFFF) was overwriting the beginning of the `banked_payload` (relocated to $EB00). Specifically, `ego_items.s` was being corrupted. When `item_spawn_level` called `tramp_roll_ego_type`, it jumped into the overwritten memory, leading to an eventual crash in the main segment code.
- **Resolution:** Moved `special_rooms.s` and `ego_items.s` to the end of the `banked_payload` block. Since the total payload size is ~4.6KB and it starts at $EB00, the last ~700 bytes (which include these critical shared routines) now reside at $F900+, safely beyond the largest 4KB overlay.
- **Rule:** **Always verify overlay overlap with resident banked code.** On the C128, ensure that any code in the $EB00-$EFFF range is truly disposable while an overlay is active. If shared code is needed *during* overlay execution, it must be placed at $F000+ or included within the overlay itself.

## C128 Zero Page KERNAL Collisions

- **Issue:** Intermittent garbled text appearing dynamically on the VDC screen during combat and UI printing.
- **Root Cause:** C128 utilizes `$02-$08` for hardware operations and pointer temp storage, particularly the `JSRFAR` routines executing during `IRQ` contexts (like screen editor blinking, and timers). The game allocated hot global pointers (`zp_ptr0`, `zp_ptr1` etc) to `$06`-`$0B` which meant background tasks or routines indirectly invoking ROM would silently clobber data strings right in the middle of long decoding loops (e.g. printing `Take off which item...`).
- **Resolution:** Relocated the vital pointers upwards to the `$13-$1F` boundaries which are completely reserved and out of scope of C128 MMU primitives.
- **Rule:** **Never use `$02-$0C` on the C128 for volatile pointers**. Treat it as effectively hazardous since the Kernel expects it available when handling interrupts.

## Verifying Implementations Against Documentation

- **Pattern:** I falsely claimed that features (Black Market and Player Home) were missing because I found old references/TODOs in `AUDIT.md` or `BUILDPLAN.md` without verifying the actual source code or `BUILDPLAN_HISTORY.md` which contained the completion status.
- **Rule:** Before claiming a feature is missing or unimplemented based on a TODO list or design document, ALWAYS `grep_search` the codebase for the feature name (e.g., "Black Market", "Home") to confirm if the code actually exists. Documentation can be stale, but the source code is the ultimate truth.

## Test-First Principle for Memory and Banking

- **Pattern:** Drafted a complex optimization plan (VDC Line Buffers) without including unit tests for the core new routine (`mmu_copy_map_row`) in the initial proposal.
- **Root Cause:** Focused purely on the algorithmic solution (Painter's Algorithm, unrolled loops) instead of the project's strict `AGENT.md` mandate: "Never mark a task complete without proving it works" and "Write plan to tasks/todo.md with checkable items... verify before implementation." For low-level memory operations, failure to test in isolation inevitably leads to invisible overwrites and CPU JAMs.
- **Rule:** **If writing a new memory manipulation, banking, or copy routine, the very first step in the implementation plan MUST be to write an isolated unit test for it.** Prove the routine handles boundaries correctly and doesn't clobber surrounding RAM *before* integrating it into the game loop.

## Processor Status (`plp`) clobbering Carry Flag Returns

- **Issue:** `clc` or `sec` used to return a success/failure status from a subroutine is immediately wiped out by a subsequent `plp` instruction right before the `rts`.
- **Root Cause:** A subroutine starts with `php` to save the caller's processor status. Before returning, it sets or clears the carry flag to indicate a result to the caller. However, if `plp` is executed *after* setting the flag and *before* `rts`, it restores the original processor status from the stack, completely overwriting the newly set/cleared carry flag. This causes the caller to receive whatever the carry flag happened to be when the subroutine was entered, rather than the intended result, leading to silent logical failures like cache misses.
- **Resolution:** If a subroutine uses `php`/`plp` and uses the carry flag for its return value, the `plp` must occur *before* the `clc` or `sec` instruction. (e.g., `plp` then `clc` then `rts`).
- **Rule:** **Never place `plp` immediately after `clc` or `sec`** when those flags are intended as return values. Always execute `plp` first to restore the original state, and *then* modify the specific flag(s) you are using to return status.

## Stop Patching Before Reconfirming the Failing Region

- **Issue:** I kept changing the summary/display path even after monitor traces no longer pointed there.
- **Root Cause:** I let an early hypothesis drive several edits instead of re-anchoring on the latest evidence from the monitor. Once the PC moved to `$E58A` inside the startup overlay, the active failure domain was chargen background generation, not summary display.
- **Resolution:** When low-level debugging produces a new PC / backtrace, treat that as the current source of truth and rebuild the plan around that region before making more code changes.
- **Rule:** **If the latest trace points to a different subsystem than the current hypothesis, stop editing and re-plan from the new trace before proceeding.**

## 2026-03-18 lesson 2
- When a new monitor trace moves the failure to a different address range, stop attributing it to the prior subsystem. Re-anchor the investigation on the new PC/backtrace before proposing next steps.

## 2026-03-18 lesson 3
- On C128, do not assume a low address like `$1000` is callable just because the symbol resolves there. First prove which bank is visible at the call site and whether the address lies in common RAM or bank-private RAM.

## Low-RAM Runtime Code vs. Bank Ownership (C128)

- **Issue:** A long-running C128 `JAM` after character creation looked like chargen/summary corruption, but the active crash was a direct `JSR $1000` into garbage during the first town render.
- **Root Cause:** `viewport_update` / `render_viewport` were linked at low RAM `$1000`, `runtime.low.prg` had no real Stage 2 runtime loader, and the initial repair loaded it into **Bank 1** even though normal gameplay runs in `MMU_ALL_RAM` (**Bank 0**) and `$1000-$3FFF` is not bottom common RAM. The callsite was correct; the residency assumption was wrong.
- **Resolution:** Prove the execution context first: identify the visible bank at the callsite, confirm whether the target address is common or bank-private, then make the loader/header match that execution model. In this case, `runtime.low.prg` needed a `$1000` PRG header and a startup loader into **Bank 0** low RAM, not Bank 1.
- **Rule:** **For any callable low-RAM segment on C128, verify all three together before patching: (1) symbol address, (2) visible bank at the callsite, and (3) common-vs-private RAM ownership.** Never infer one from the others.

## PETSCII Disk Names vs. Source-Friendly Names

- **Issue:** I renamed the low-RAM runtime payload to `runtime_low.prg`, but the C128 directory display rendered `_` as a shifted graphic, not a readable underscore.
- **Root Cause:** I optimized for source readability instead of the actual PETSCII on-screen filename that users see in the disk directory and preload list.
- **Resolution:** For user-visible C64/C128 disk asset names, prefer characters that render cleanly in PETSCII directory listings. In this case, `runtime.low.prg` is the correct name and the on-disk filename bytes must match the displayed string exactly.
- **Rule:** **When renaming a Commodore disk file, verify the actual PETSCII directory rendering, not just the source string or host filename.**

## Corrections From the 2026-03-18 Inventory-Help Regression

- **Issue:** I changed the banked payload copy routine based on the inventory-help IRQ trace, but the new helper caused an earlier startup `BRK` before overlays loaded.
- **Root Cause:** I optimized around the vector-overwrite symptom without preserving the original page-`$FF` copy contract. On C128, `$FF00` is the MMU control register, so a naive tail copy into `$FF00-$FFC4` is not safe even if it avoids `$FFFA-$FFFF`.
- **Resolution:** When page `$FF` is involved, enumerate every special address in that window (`$FF00`, RAM vectors, ROM-shadowed helpers) before replacing an existing copy strategy. In this case the safer repair is to restore runtime vectors on banked UI exit, not redesign the copy loop under pressure.
- **Rule:** **If a fix touches C128 page `$FF`, prove every special address in `$FF00-$FFFF` remains safe before changing the routine. Do not replace a specialized copy strategy with a generic one on inference alone.**

## Banked Payload Source vs. Runtime Window (C128)

- **Issue:** Help/inventory/equipment screens could blank or half-render only after overlay activity, even though the resident banked UI code itself lived safely at `$F000-$FFFA`.
- **Root Cause:** I focused on the resident runtime addresses but missed that the **source bytes** for `init_copy_banked` were staged in the main image across `$D6xx-$E6xx`. Because that source span overlaps the overlay load window at `$E000-$EFFF`, any later recopy after an overlay load can silently reintroduce corruption into the otherwise-safe resident `$F000` banked window.
- **Resolution:** For any copied resident block, verify both:
  1. the destination/runtime window is safe, and
  2. the source/staging window does not overlap transient overlay or loader regions that can mutate before the next copy.
- **Rule:** **On C128, overlay-safety analysis must cover both the resident destination and the staged copy source. A resident block can still be corrupted if its recopy source overlaps `$E000-$EFFF`.**

## I/O-Hole Placement Drift (C128)

- **Issue:** Town -> dungeon descent `JAM`ed during `item_spawn_level`, even though the trampoline path itself stayed below `$D000`.
- **Root Cause:** I only asserted the trampoline placement and missed that the callee (`roll_ego_type`) had drifted to `$D310`, inside the `$D000-$DFFF` I/O hole. The PRG contained code there, but runtime execution with I/O visible read garbage.
- **Resolution:** For any banked/trampolined C128 call path, verify both sides of the jump: the caller/trampoline location and the callee’s runtime residency. If the callee must execute with I/O visible, it cannot live in `$D000-$DFFF`.
- **Rule:** **On C128, “trampoline below `$D000`” is not enough. Every callable target in that path must also be asserted out of the I/O hole or explicitly executed with a no-I/O banking mode.**

## Harness Optimizations Need Runtime Verification

- **Issue:** I changed `run_tests128.sh` for `OPT-TEST`, and `bash -n` passed, but the real runner broke badly: helper functions were not visible inside `xargs` worker shells, and a layout guard still enforced an obsolete banked-UI contract.
- **Root Cause:** I treated syntax validation and ad hoc sourcing as enough proof for a shell harness change. That missed two real execution contexts: exported functions in child shells and stale assertions inside the harness itself.
- **Resolution:** For shell-runner changes, always validate the actual execution mode:
  1. run the real target (`make -C commodore/c128 test128` or a focused sourced runner path),
  2. check any `xargs` / subshell worker paths explicitly, and
  3. update harness assertions when the underlying architecture contract has changed.
- **Rule:** **A shell harness change is not verified by `bash -n`. It must be exercised through the same subshell/worker path the real test runner uses.**

## Shell Passes Do Not Imply Snapshot Readiness

- **Issue:** I initially treated `memory128`, `msg_prompt128`, and `tier128` as ready for the Python Gate C.4 batch harness because they passed under the shell moncommands runner.
- **Root Cause:** The shell path (`load` + `r pc=` + `until`) and the Python cold/snapshot paths do not reproduce the same machine state. A test can be valid under the shell harness yet still be invalid under the current ready-snapshot contract or the Python reset model.
- **Resolution:** Promote a test into the default Python batch set only after it passes in both:
  1. direct Python cold mode, and
  2. Python snapshot mode using the current prepared snapshot contract.
  If either path is not trustworthy, mark the test explicitly unsupported instead of leaving it in the default compare set.
- **Rule:** **For Gate C.4, shell-harness success is necessary but not sufficient. A test is only “snapshot-ready” after direct Python cold/snapshot verification.**

## Moncommands Paths Must Match Exactly

- **Issue:** I initially classified several Gate C.4 tests as incompatible with the Python batch harness when they were really failing because the Python moncommands path did not match the shell harness execution contract.
- **Root Cause:** The Python moncommands runner omitted `+remotemonitor +binarymonitor` and the per-test `-limitcycles` budget. That left VICE alive at the monitor prompt and produced false timeout failures.
- **Resolution:** When reproducing a shell-based VICE flow in Python, mirror the full invocation contract before concluding a test is incompatible. For moncommands-driven tests, carry over the shell runner’s flags and cycle budgets explicitly.
- **Rule:** **If a Python VICE harness disagrees with the shell harness, compare the exact emulator invocation first. Missing VICE flags or cycle budgets can look like test failures.**

## Symbol Width Is Not Enough To Choose A Harness Path

- **Issue:** I initially assumed only wrapped/wide symbol addresses needed the moncommands fallback. `input128` disproved that assumption.
- **Root Cause:** The `symbols_need_moncommands()` heuristic only captures one class of incompatibility. Some tests with ordinary 16-bit symbols still require the shell-style moncommands contract to execute correctly.
- **Resolution:** Treat moncommands-vs-socket execution mode as explicit per-test metadata once a test proves it needs that path. Do not rely on symbol width alone as the selector.
- **Rule:** **For Gate C.4, “4-digit symbols” does not imply “safe for socket-run execution.” Use explicit per-test execution metadata when needed.**

## Closed Technical Fixes vs Misleading Names

- **Issue:** I answered as if the low-RAM runtime payload issue was fully “done,” but the user was pointing at the still-misleading artifact name, not just the runtime loader contract.
- **Root Cause:** I collapsed two separate concerns into one: the runtime fix (load/address contract) and the naming/architecture clarity problem.
- **Resolution:** When a historical bug involved both runtime behavior and confusing naming, answer both explicitly: what is fixed in code, and what remains misleading in naming/docs. Then actually clean up the naming so future work does not preserve the confusion.
- **Rule:** **Do not call a historically expensive issue “fully fixed” if the naming still contradicts the runtime contract. Distinguish behavioral closure from naming/architecture clarity, and fix both when possible.**

## Commit Policy Must Be Explicit

- **Issue:** I committed the running fix as soon as verification was complete without waiting for explicit user approval.
- **Root Cause:** I treated the repository's frequent commit cadence as implicit permission instead of checking for an explicit "OK to commit" signal in the current task.
- **Resolution:** Treat commit authority as opt-in for the current task unless the user has clearly told me to commit when done. Verification and documentation can complete before that point, but the final `git commit` must wait for explicit approval.
- **Rule:** **Do not commit changes in this repo until the user explicitly says to commit, even if the code is done and fully verified.**
- **Follow-up:** The recent town-entry regression and subsequent fix were committed before the user said “OK,” so this is a second reminder that every task ends with an explicit approval step.

## 2026-03-20 — Bank 1 cannot execute bank 0 code

- **Issue:** Entering town after the row-buffer changes triggered a JAM in `mmu_select_bank1` (`C:$01F8`) because the new loop executed while Bank 1 was active, so the CPU fetched the wrong instructions.
- **Root Cause:** `map_bulk_enter` was called before the `row_char_buf` copy loop, leaving Bank 1 selected while the renderer kept executing Bank 0 code; the bytes under Bank 1 at the same addresses were not valid instructions, so the CPU fell into an illegal opcode.
- **Resolution:** Use the `mmu_copy_map_row` helper to pull the entire row into the shared scratch buffer while Bank 1 is active, return to Bank 0, and then copy from `SCREEN_RAM` into `row_char_buf`; this keeps us executing Bank 0 code with Bank 0 visible and relies on the bank-safe helper for the single transition.
- **Rule:** **Whenever a bank switch is required for data access, either run the affected code entirely from a helper located in that bank/common area or switch back before executing Bank 0 code; do not run Bank 0 instructions while Bank 1 is still selected.**
## Premature Running Stop Needs Runtime Diagnosis First

- **Issue:** I treated the user's "running stops too early" report as a corridor-stop-policy problem and patched `run_check_stop` / `run_check_intersection`, but manual testing showed the real symptom did not change.
- **Root Cause:** I anchored on the static code discrepancy (missing floor-item stop and oversensitive side-junction logic) without first proving that the observed stop was actually coming from those branches. The reported fixed-distance stop in both town and dungeon suggests the real cause is in run continuation/cancel handling, not corridor geometry.
- **Resolution:** For movement/running bugs, first classify the symptom by behavior pattern: geometry-sensitive stop, sight-sensitive stop, or fixed-distance/cancel stop. If the stop distance is roughly constant across town and dungeon, inspect input/run-cancel state before touching map-intersection logic.
- **Rule:** **Do not patch running stop-policy code until the observed stop pattern has been tied to that code path. A fixed-distance stop pattern points to run continuation/cancel logic first.**

## One-Sample Run-Cancel Edges Are Too Fragile

- **Issue:** I left the running cancel path on a one-sample edge detector after the earlier fix. After the 10.3 map expansion, the user immediately hit early running cancellation again.
- **Root Cause:** The run-cancel detector treated any single nonzero sample as a fresh cancel edge once armed. That is too fragile for direct keyboard scanning, especially when frame cadence changes and scan noise gets more opportunities to land as a transient sample.
- **Resolution:** Normalize run-cancel samples to boolean held/not-held state and require a newly-stable pressed state before emitting a cancel edge. Keep the logic shared across C64/C128 so behavior does not drift again.
- **Rule:** **For direct-scan run cancel, do not use a one-sample raw-key edge. Use a debounced boolean held-state edge detector.**

## Running Must Use Physical Held State, Not Decoded PETSCII

- **Issue:** After the debounce fix, C128 running still stopped after a few steps while C64 behaved correctly.
- **Root Cause:** The C128 running path was still sampling `cia_scan_petscii` for held/cancel state. Shifted run movement depends on PETSCII decoding staying visible, but running logic only cares whether the initiating keys are physically still down.
- **Resolution:** Use a raw matrix-held helper for `input_run_key_held` and `input_run_cancel_check` on C128, matching the C64 contract. Keep PETSCII decoding for command entry, not held-state detection.
- **Rule:** **For held/cancel polling, sample physical key state. Do not route running through PETSCII decoding on C128.**

## Corridor door placement must reflect actual tunnel penetration

- **Issue:** `add_corridor_doors` used to synthesize lateral doors whenever a corridor tile ran next to a room wall, which cluttered hallways with phantom doors and confused both running heuristics and dungeon semantics.
- **Resolution:** Make the helper a compatibility stub, remove the `dungeon_generate` call, and rely on `carve_h_corridor` / `carve_v_corridor` plus `random_door_type` to place doors only when a corridor actually breaches a wall. The new `commodore/c64/tests/test_dungeon.s` cases prove adjacency alone does not produce a door while actual penetration still does.
- **Rule:** **Door placement must always occur during corridor carving; never add a door solely because a corridor tile lies adjacent to a room wall. Tests must guard the contract on both adjacency and penetration conditions.**

## 2026-03-21 — Respect explicit revert requests

- **Issue:** After a user observed the new OPT-VDC stack hung the dungeon/town creation code and demanded a rollback, I continued the work rather than pausing to revert everything that wasn’t the 2 MHz tweak.
- **Resolution:** Roll back all OPT-VDC changes before making any other edits, even if debugging traces look promising, and keep only the CPU speed toggle the user explicitly ordered to keep.
- **Rule:** **When a user explicitly orders “revert everything except…”, stop implementing new features, revert the tracked/untracked files to the requested state, and log the correction in `tasks/lessons.md` immediately (with a reminder to obey future direct corrections).**

## 2026-03-22 — Check room-level and tile-level lighting state together

- **Issue:** The long-standing dark-room "flash" on item pickup or monster death looked like a redraw bug, but the real failure was stale lighting state.
- **Root Cause:** `room_lit[]` and per-tile `FLAG_LIT` could drift apart, so a forced full redraw after pickup/kill would render the room as lit even though the room tiles had not been synchronized to that state.
- **Resolution:** Add one authoritative helper to light an entire room and make room-light effects use it, so room-level and tile-level lighting state stay synchronized before investigating renderer-specific causes.
- **Rule:** **When a visibility or redraw bug affects entire rooms, check room-level state (`room_lit[]`, room caches) against per-tile flags before changing renderer logic.**

## 2026-03-22 — Close completed work in both active and history docs

- **Issue:** After fixing BUG-LIT and adding the completed history entry, I still left the active build plan stale, so the resolved bug was not reflected in `commodore/BUILDPLAN.md`.
- **Root Cause:** I treated `BUILDPLAN_HISTORY.md` as sufficient for closure and did not re-check whether the active status summary also needed to be updated to reflect the completion.
- **Resolution:** When closing a task that is mentioned in planning docs, update both the archival completion record and the active build-plan state in the same pass, then verify the result with a direct grep.
- **Rule:** **If a bug or phase is closed, do not stop at `BUILDPLAN_HISTORY.md`. Also reconcile `commodore/BUILDPLAN.md` so the active plan no longer contradicts the completion record.**

## 2026-03-22 — Do not close a multi-cause bug after fixing only one trigger

- **Issue:** I declared BUG-LIT fixed after correcting the `room_lit[]` / `FLAG_LIT` drift, but the user immediately reproduced another dark-room pickup case that still revealed hidden room tiles.
- **Root Cause:** I treated one verified sub-cause as if it exhausted the whole bug class, without requiring a broader repro matrix or a test that matched the original gameplay symptom closely enough.
- **Resolution:** Reopen the bug as soon as a real repro survives, keep the partial fix, and do not mark the overall issue complete until at least one targeted test or manual matrix covers the remaining symptom family.
- **Rule:** **For long-standing rendering bugs with multiple plausible causes, do not close the umbrella bug after fixing one trigger. Keep it open until the original gameplay repro family is actually covered.**

## 2026-03-22 — Do not generalize a bad tool invocation into a global environment claim

- **Issue:** After my C64 headless test invocation crashed, I claimed that VICE itself was broken in this environment.
- **Root Cause:** I inferred a broad environment failure from one failing command sequence without validating the simpler counterexample: whether `/opt/homebrew/bin/x64sc` itself ran normally outside my exact headless/autostart setup.
- **Resolution:** Treat failures like this as invocation-specific until proven otherwise. Separate "this command line crashed" from "the tool is broken," and say exactly which invocation failed.
- **Rule:** **Never claim a tool/environment is generally broken when only one scripted invocation has failed. State the exact failing command path and keep the scope narrow until independently confirmed.**

## 2026-03-22 — Keep umbrella bug status narrower than individual trigger fixes

- **Issue:** BUG-LIT turned out to have multiple trigger paths, and after fixing the pickup/full-redraw path I still needed the docs to reflect "one trigger fixed, umbrella still open."
- **Root Cause:** I had already made the mistake in the opposite direction earlier by declaring the whole bug fixed after one sub-cause. The durable rule needs to be symmetric: doc status must match the exact scope of what was just proven.
- **Resolution:** When a multi-cause bug is partially fixed, record exactly which trigger is closed and keep the umbrella item open until the remaining trigger family is rechecked.
- **Rule:** **For multi-trigger bugs, document the exact trigger path that is fixed. Do not collapse partial progress into either "fully fixed" or "still unchanged."**

## 2026-03-22 — Keep BUILDPLAN for backlog, not guardrails

- **Issue:** I reorganized `commodore/BUILDPLAN.md` into a single open-items table, but I mixed real backlog items with merge guardrails like “keep the suite green” and “preserve memory ownership,” which made the table harder to read and less useful.
- **Root Cause:** I treated every true project constraint as if it belonged in the same artifact as actionable work. That conflates two different purposes: planning outstanding tasks versus recording engineering discipline.
- **Resolution:** Keep `BUILDPLAN.md` for actual open bugs, features, phases, and cleanup work. Put “don’t break this” operational rules in `AGENTS.md`, `tasks/lessons.md`, asserts, and tests instead.

## 2026-03-23 — Do not invent cross-platform input portability doubts without evidence

- **Issue:** I pushed back on a fixed `Ctrl+W` Wizard Mode hotkey by speculating that the key might not be portable across C64 and C128.
- **Root Cause:** I ignored established project knowledge: the platforms differ in polling implementation, but the actual command-key identity layer is already aligned.
- **Resolution:** Treat proven command-mapping parity as the default. Only argue for an implementation-defined hotkey if the actual key identity differs in code or observed behavior.
- **Rule:** **Do not raise speculative cross-platform input objections when the repo already standardizes the key mapping across platforms. Require evidence before arguing for a flexible hotkey.**

## 2026-03-22 — Do not repurpose the live `$E000` overlay window for resident compute code

- **Issue:** I moved `player_magic.s` into a reloadable `$E000` compute payload because the symbol layout and fast C128 suite looked good, but live gameplay immediately corrupted character creation and town/spell paths.
- **Root Cause:** `$E000-$EFFF` is not an abstract “free reloadable code window.” It is the active startup/town/death/dungeon-generation overlay execution region, and those overlays are live earlier and more often than the focused tests proved. Recopying spell compute code there destroyed the active overlay image.
- **Resolution:** Reject `$E000` as a general-purpose resident compute relocation target for shared gameplay code. Any future relocation must use a region that is not the active overlay execution window, or it must come with explicit overlay coexistence proof in real gameplay.
- **Rule:** **On C128, do not move shared gameplay compute code into `$E000-$EFFF` just because it is reloadable. Treat the overlay window as owned by overlays unless coexistence is explicitly proven in live game flows, including startup/chargen.**
- **Rule:** **Do not put ongoing engineering guardrails into the active backlog table. `BUILDPLAN.md` should answer “what is left to do?”, not “what must always stay true?”**

## 2026-03-22 — Assert the whole callable routine, not just its entry label

- **Issue:** Casting still JAMmed at `$D013/$D023` even after the relocation work looked clean and the old C128 assert said `trace_step < $D000`.
- **Root Cause:** That assert only checked the routine entry label. `trace_step` started at `$CFF7` but its body extended into `$D000-$DFFF`, so runtime execution still fetched garbage from the I/O hole.
- **Resolution:** Treat I/O-hole safety as a whole-routine placement problem. In this case the right fix was to relocate the projectile helper routines into the copied common combat window and update the assert to cover that actual residency contract.
- **Rule:** **On C128, never assert only that a callable symbol starts below `$D000`. Also prove the routine body cannot execute into `$D000-$DFFF`, or relocate the routine into a region with a stronger contract.**

## 2026-03-22 — Do not stack speculative prompt and redraw fixes on top of a working input guard

- **Issue:** After fixing the spell-list entry key edge, I layered on an extra post-selection release wait, a special no-release direction prompt, and an extra `update_visibility` during spell-list restore. That regressed spell casting again and muddied the BUG-LIT signal.
- **Root Cause:** I kept “improving” a narrow input fix without evidence that the first correction was insufficient. That combined three different concerns: key-edge handling, nested prompt behavior, and visibility/redraw state.
- **Resolution:** Roll back the extra nested-prompt and redraw changes, keep only the original spell-selection release guard, and re-test from that narrower baseline.
- **Rule:** **When an input fix works, do not immediately pile on prompt-specialization and redraw-state changes. Keep the minimal guard first, then re-test before changing adjacent systems.**

## 2026-03-22 — `$0800-$0BFF` is not safe permanent executable space for C128 gameplay code

- **Issue:** I relocated the combat/spell spill cluster into a copied common-RAM blob at `$0800-$0BFF`. Spell casting started to work, but the death path still hung deep inside ROM with traces like `C:$E7F2  LDA $0A0F`.
- **Root Cause:** Under `MMU_NORMAL`, those `$E7xx` addresses are KERNAL / Screen Editor ROM, not our overlays. ROM was reading low RAM around `$0A0F`, which the new combat blob had overwritten. So `$0800-$0BFF` is part of ROM workspace expectations during KERNAL-visible flows and cannot be treated as permanently safe code storage.
- **Resolution:** Abandon the `$0800-$0BFF` relocation design entirely and revert the branch to the last stable baseline.
- **Rule:** **On C128, do not treat `$0800-$0BFF` as free permanent executable common RAM for gameplay code unless you have explicit proof it survives all KERNAL/ROM paths. A ROM trace reading that region is evidence the design is invalid, not a cue to patch around it.**

## 2026-03-22 — Shared C64/C128 file splits must preserve the non-C128 import path

- **Issue:** Splitting `player_magic_tail.s` out for C128 banked placement broke the C64 build because `mage_effect_dispatch` and `priest_effect_dispatch` disappeared from the non-C128 link path.
- **Root Cause:** I treated a shared-file split as if only the C128 placement changed, but the shared source graph changed too. C64 still imported only `player_magic.s`, so the split silently removed required symbols there.
- **Resolution:** When factoring shared code for C128-only residency, explicitly retain the non-C128 import path in the shared source and immediately rebuild C64 before treating the change as valid.
- **Rule:** **Any C128-only relocation that splits a shared source file must preserve the non-C128 import graph and be followed immediately by a C64 build check.**

## 2026-03-23 — Runtime-installed busy shims must be proven live, not just referenced

- **Issue:** The generation spinner logic was wired into `game_loop.s` and `turn.s`, but the player still only saw the old `Loading...` message and never the full-screen `GENERATING...` UI.
- **Root Cause:** The gameplay path called `generation_busy_*_api`, but those symbols still assembled to default `RTS` stubs because startup never patched them live. I verified the call sites and not the installed shim bytes.
- **Resolution:** Convert the busy API to an explicit startup-installed jump table, patch it during platform startup, and use the shared `generation_busy_active_api` state for any suppression logic that depends on the UI being active.
- **Rule:** **For startup-installed shim APIs, verify both that the game calls the shim and that startup patches the shipped stub bytes before gameplay begins. Referenced symbols alone do not prove the feature is live.**

## 2026-03-23 — Do not inject UI helpers into generation inner loops that still own live scratch state

- **Issue:** After the busy UI finally appeared, the initial town map came up corrupted.
- **Root Cause:** I had added `generation_busy_tick` calls inside dungeon-generation inner loops (`place_rooms`, `connect_rooms`, `place_streamers`). Those loops still owned generator scratch/register state, and the UI helper clobbered it.
- **Resolution:** Keep progress UI calls only at coarse, explicitly safe phase boundaries unless the callee contract is proven re-entrant with the generator’s scratch usage.
- **Rule:** **For long-running generation/codegen loops, do not call screen/UI helpers from inside inner loops unless scratch/register ownership has been audited end-to-end. Prefer outer phase boundaries.**

## 2026-03-23 — C64 `msg_print` strings must be screen-coded, and banked UI fixes must be re-budgeted immediately

- **Issue:** C64 Wizard actions like Reveal and Generate Item showed junk text (`8&>e`) instead of the expected completion message, and the follow-up fix work kept brushing against the C64 banked-vector ceiling.
- **Root Cause:** I introduced Wizard strings in a shared/common file with plain `.text` bytes while the C64 message renderer expects screen-code strings. Separately, I treated small common/UI tweaks as if they were “free,” even though the C64 banked payload was already only a few bytes from `$FFFA`.
- **Resolution:** Emit C64-facing Wizard/message strings with the correct screen-code encoding, then immediately rebuild and read the banked payload boundary after any shared banked-UI change. If space is needed, trim low-value banked UI text rather than touching logic again.
- **Rule:** **On C64, any string that goes through `msg_print` or `screen_put_string` in gameplay UI must be verified as screen code, not assumed from `.text`. After any shared banked UI change, re-check `banked_code_end` before assuming the fix is safe.**

## 2026-03-23 — C128 fast command input can race on modifier chords

- **Issue:** `Ctrl+W` worked on C64 but on C128 it fell through to a plain gameplay command instead of opening Wizard Mode.
- **Root Cause:** The C128 fast command-entry path accepts the first stable key-down sample immediately. For a chord like `Ctrl+W`, the `W` sample can arrive one scan before the Ctrl modifier settles, so the command path locks in plain `W` unless the chord is normalized after acquisition.
- **Resolution:** Recheck live Ctrl state for `W` immediately after fast key acquisition and normalize it to the Wizard pseudo-key before PETSCII-to-command decode. Keep the runtime fix compact, and cover the pure normalization rule in a unit test.
- **Rule:** **On C128, do not assume modifier chords are stable on the first fast input sample. For any modifier-based command, verify whether the command-entry path needs a post-acquisition normalization step.**

## 2026-03-23 — Do not merge Magic Mapping and global light into one Wizard reveal action by guesswork

- **Issue:** Wizard Reveal was implemented by setting `FLAG_VISITED | FLAG_LIT` across the whole map, forcing every room lit and piggybacking on the visibility-update redraw tail. On C64 that produced incorrect-looking results and led to a post-reveal crash.
- **Root Cause:** I guessed at the semantics of “reveal” instead of checking the actual classic behavior split. In Umoria, Magic Mapping and global overhead light are separate Wizard commands, so collapsing them into one blanket-lighting action was too blunt.
- **Resolution:** Make Wizard Reveal do mapping-only semantics (`FLAG_VISITED` without global `FLAG_LIT` / `room_lit` mutation), redraw through the plain gameplay restore path, and only add a separate global-light command later if we explicitly want it.
- **Rule:** **When cloning classic Wizard/debug commands, verify whether upstream separates “map memory” from “global light” before implementing a one-step reveal action.**

## 2026-03-23 — Overlay-resident C128 UI code cannot keep running after loading a different overlay

- **Issue:** C128 Wizard level jump reached generation and then got stuck on the busy screen. The monitor trace showed the game back in `input_get_command`, meaning control had returned to the main loop without restoring the gameplay view.
- **Root Cause:** `ui_wizard_cmd_level_jump` lived in `OVL.UI` at `$E000`, but it tried to call `overlay_load(OVL_DUNGEON_GEN)` and then continue executing more Wizard code from the same overlay window. Once the new overlay was loaded, the remaining Wizard code in `$E000` was no longer valid.
- **Resolution:** Move the actual level-jump execution tail into main-resident code and let the overlay UI only collect input and then jump to that stable main routine.
- **Rule:** **On C128, any command handler that lives in an overlay must not continue executing after swapping in a different overlay. Collect input in the overlay, then transfer control to main- or banked-resident code before `overlay_load` of another overlay.**

## 2026-03-23 — If Wizard Mode is meant to force an outcome, call the shared effect helper directly

- **Issue:** Wizard `Gain Level` kept doing nothing in manual play even though the code path looked equivalent to normal XP-driven level-up.
- **Root Cause:** I kept routing Wizard `Gain Level` through `combat_check_levelup` because the threshold/XP setup looked correct on inspection. That was the wrong level of abstraction for a forced Wizard action, and I trusted code symmetry over manual evidence.
- **Resolution:** Extract the actual level-up body into `combat_apply_levelup` and have Wizard `Gain Level` call that shared helper directly after seeding XP, instead of reusing the ordinary threshold gate.
- **Rule:** **When a Wizard/debug action is supposed to force a state transition, do not keep it behind the normal gameplay eligibility wrapper once manual testing disproves that path. Extract and call the real shared effect helper directly.**
- Wizard/debug commands should reuse existing gameplay reveal/effect helpers where possible; ad hoc map-flag edits miss side effects like secret-door conversion.
- For map-reveal/debug features, do not mark the whole map `FLAG_VISITED` blindly; that exposes solid-rock filler and produces misleading layouts on deep levels. Reveal the floor plan, then add corridor boundaries and reuse existing door/trap reveal helpers.

## 2026-03-23 — When a rare C128 gameplay helper does not fit low runtime, prefer an overlay over forcing it into resident banks

- **Issue:** I moved `magic_check_new_spells` out of the I/O hole by pinning it in `RuntimeLowData`, which fixed the immediate `$D023` JAM but immediately overflowed the `$1000-$19FF` low-runtime ownership fence at `FLOOR_ITEM_BASE`.
- **Root Cause:** I treated “low runtime is resident” as the default safe destination without re-checking its real ownership budget. That region is tightly bounded by floor-item and creature tables, so a one-off helper there can be just as wrong as leaving it in the I/O hole.
- **Resolution:** Move the helper into `OVL.UI` and make the C128 trampoline load that overlay before calling it. For low-frequency helpers like learned-spell updates, overlay residence is safer than overfilling either low runtime or the resident `$F000` payload.
- **Rule:** **On C128, when relocating a low-frequency helper out of the I/O hole, do not force it into `RuntimeLowData` or the resident banked payload by default. First ask whether an existing overlay is the safer ownership match.**

## 2026-03-23 — Verify sentinel assumptions against live table indexing before patching a display path

- **Issue:** After adding save/restore protection for the death source, the death screen still showed `Unknown Causes` for some Wizard deaths.
- **Root Cause:** I assumed `zp_death_source == 0` meant "alive/unknown" because of a stale zeropage comment and matching fallback branch in `score.s`. In reality, monster index `0` is a valid creature (`White Harpy`), so the death screen was misclassifying real monster deaths as unknown.
- **Resolution:** Check the actual indexed table owner (`monster.s`) before trusting sentinel comments, then treat any non-special `zp_death_source` as a monster id in the death screen.
- **Rule:** **Whenever a byte is documented as a sentinel-bearing enum, verify that claim against the real indexed data tables before writing fallback logic around value `0`.**

## 2026-03-23 — When shuffling room order, keep all parallel room metadata arrays in lockstep

- **Issue:** Lit rooms started behaving like dark rooms even with a lantern equipped; only torch/LoS visibility still worked.
- **Root Cause:** `shuffle_rooms` was only swapping `room_x`, `room_y`, `room_w`, and `room_h`. It left `room_lit[]` behind, so the room geometry and the “this room is lit” flag drifted apart after generation.
- **Resolution:** Treat `room_lit[]` and other room-parallel metadata as part of the shuffled room record, and extend the dungeon test to verify the metadata stays aligned with the shuffled geometry.
- **Rule:** **Whenever SoA room records are reordered, audit every parallel array (`room_*`) and update the shuffle/copy path for all of them, not just geometry.**

## 2026-03-23 — Wizard item generation must reuse the real item-initialization path

- **Issue:** Wizard `Generate Item` reported `FAIL` for ordinary items like `Brass Lantern`, and even a “successful” raw spawn would have created unusable lights/wands/staves with zero charges.
- **Root Cause:** The Wizard command was hand-writing a bare floor item entry with `p1=0` and relying on floor placement success. That skipped the normal item initialization path (`roll_enchantment`, charges, ego rolls, ammo stack sizing) and made the command depend on floor-slot state instead of producing a usable test item.
- **Resolution:** Route Wizard item generation through the normal item-creation helpers, prefer inventory placement for non-gold items, and only fall back to floor placement if inventory insertion fails.
- **Rule:** **Wizard/debug item creation should not hand-assemble raw item structs unless the intent is explicitly “broken placeholder item.” Reuse the normal item initialization helpers so charges, enchantment, ego flags, and stack sizing stay coherent.**

## 2026-03-23 — Do not claim original-game behavior without a primary source

- **Issue:** I talked about the current carried-light radius as if it were plausibly faithful to original Umoria, even though I had not verified the original game’s exact numeric behavior.
- **Root Cause:** I generalized from the current port implementation and broad manual language about lamps/torches instead of checking whether the original game actually specified the radius or differentiated torch vs lantern reach.
- **Resolution:** When the user asks for original-game parity, either verify the exact behavior in primary Umoria sources or say explicitly that the precise rule is still unverified and needs research.
- **Rule:** **For historical-faithfulness questions, do not infer a specific gameplay parameter from the current port. Verify it in primary sources or turn the gap into explicit backlog research.**

## 2026-03-23 — When shared gameplay code gains a new helper dependency, update the shared C64 test stubs immediately

- **Issue:** The BUG-RECALL refactor made `turn.s` call `level_change_generate_current`, and a large set of C64 unit suites started failing at assembly with `Unknown symbol 'level_change_generate_current'`.
- **Root Cause:** I updated the focused recall test, but I did not audit the broader C64 test harness pattern where many suites import `turn.s` plus `ui_trampoline_stubs.s` and rely on that file as the common stub surface for game-only helpers.
- **Resolution:** Add a shared no-op `level_change_generate_current` stub to `commodore/common/ui_trampoline_stubs.s` so the non-transition tests assemble again, while keeping focused tests free to override it locally.
- **Rule:** **Whenever a shared gameplay file gains a new call into main-loop/overlay transition helpers, audit the common C64 test stub surface (`ui_trampoline_stubs.s`) in the same change. Do not assume only the focused test needs updating.**

## 2026-03-23 — Test doubles must preserve the real helper contract, not just compile

- **Issue:** `test_main_loop` kept failing after the recall refactor even though the gameplay stairs path was fine.
- **Root Cause:** The test stub for `check_stairs_at_player` returned the raw tile byte (`$90`) while the real helper returns the extracted tile-type nibble (`9`). That made the harness report “no stairs” even though the real game contract was unchanged.
- **Resolution:** Make the stub mirror the real helper semantics by shifting the tile byte down before returning it, then re-run the suite under VICE to prove the failure disappears.
- **Rule:** **When patching in a test helper, copy the behavior contract as well as the symbol name. A stub that returns the wrong representation creates fake regressions and wastes debugging time.**

## 2026-03-23 — The authoritative affected-platform suite is the gate, not partial evidence

- **Issue:** I made shared-code changes, saw partial/focused test evidence, and continued working even after the user's local authoritative suite was failing.
- **Root Cause:** I treated narrower checks, partial platform coverage, and environment-specific debugging evidence as sufficient to keep moving. That violated the real contract: the repository's authoritative suite for the affected platform is the release gate.
- **Resolution:** If a change affects C64 behavior, require a clean local `make test` before calling the work done, ready, verified, or committable. If a change affects C128 behavior, require `make test128-fast`, and require `make test128` for high-risk banking/layout work. If my environment disagrees with the user's local failing run, treat the user's failing run as authoritative and keep working until that exact suite is green again.
- **Rule:** **Do not claim completion, readiness, verification, or commit-worthiness for affected-platform work until the authoritative suite for that platform passes. When the user's local run fails, that failing run is authoritative until I make the same suite pass.**

## 2026-03-23 — C64 runtime suites must keep the final BRK at the end of the "Test Code" segment

- **Issue:** `test_render.s` failed as `0/4` even though the test logic itself was fine.
- **Root Cause:** The whole suite body lived inside the `"Test Code"` segment, so `run_tests.sh` extracted the wrong breakpoint address and stopped on a helper return instead of the final BRK after copying `tc_results` to `$0400`.
- **Resolution:** Use the standard C64 bootstrap/exit-trampoline pattern: a small `"Test Code"` segment with the startup jump and exit copy loop, and keep the final BRK at the end of that segment.
- **Rule:** **If a C64 suite is run by `run_tests.sh`, the `"Test Code"` segment must end at the exit BRK that copies results to `$0400`. Do not leave the whole suite body inside `"Test Code"`.**

## 2026-03-23 — Large C64 suites that touch the dungeon map must assert they stay below MAP_BASE

- **Issue:** `test_effects.s` timed out because it silently overwrote itself.
- **Root Cause:** The suite grew into the `$C000` map region. Later dark-room/map-fill tests wrote through the dungeon map helpers and corrupted live test code/data.
- **Resolution:** Move large scratch buffers into a separate segment and add an explicit assert proving the executable test body stays below `MAP_BASE`.
- **Rule:** **For C64 suites that import map-generation/render code and also carry bulky local buffers, keep the executable test body below `MAP_BASE` and assert that contract directly.**

## 2026-03-23 — For bad-merge backlog questions, compare the merged branch against the named source branch first

- **Issue:** I started proving the stale build-plan bugs from local history/code evidence before checking the exact branch the user identified as the pre-merge source of truth.
- **Root Cause:** I anchored on the merged result first instead of diffing the bad target branch against the known-good source branch immediately. That risks catching stale reopenings while missing legitimate backlog items that were dropped by the merge.
- **Resolution:** When the user names the source branch of a bad merge, compare that branch against the merged target first and use that diff to decide both directions of the repair: what must be removed and what must be restored.
- **Rule:** **For merge-fallout doc repairs, do not patch from memory or partial history. Diff the merged branch against the user-named source branch first so stale reopenings and dropped backlog items are handled together.**

## 2026-03-24 — Before claiming a fix is ready, inspect the whole workspace and remove stray side-track edits

- **Issue:** I reported a good two-file C128 JAM fix while the workspace still contained unrelated uncommitted `main.s` / test-runner changes and a half-finished `special_rooms_banked.s`, which made the user's next local build fail.
- **Root Cause:** I validated the targeted fix but did not re-check `git status` and reconcile unrelated in-flight edits before telling the user the tree was ready to test.
- **Resolution:** Before saying a fix is ready, inspect the full working tree, build from that exact tree, and either revert or explicitly call out any unrelated uncommitted edits that could affect the user's build.
- **Rule:** **Do not present an uncommitted fix as ready until the actual workspace is clean except for intentional files, and the build/test results come from that same exact tree state.**

## 2026-03-24 — Reproduce C128 runtime bugs from the user's exact disk-image path before blaming stale artifacts

- **Issue:** I initially leaned on a "current disk image looks fine" theory even after the user was reproducing the JAM from `make clean128; make disk128`.
- **Root Cause:** I checked assembled overlay bytes and prior smokes before grounding the investigation in the exact build-and-run path the user was actually using.
- **Resolution:** For C128 boot/runtime crashes, first rebuild with the user's exact target sequence and treat that D64 path as the primary truth before narrowing the fault to runtime ownership or control flow.
- **Rule:** **When a user reports a C128 crash from a specific `make ...` disk path, reproduce from that exact path first. Do not spend time on stale-build theories until that path is ruled out.**

## 2026-03-24 — Treat `$E000` ownership as invalid after tier activation unless the overlay is explicitly restored

- **Issue:** Entering dungeon level 1 on C128 could JAM in `spawn_special_room_monsters` even though the dungeon-generation overlay had loaded correctly.
- **Root Cause:** `tier_check_transition` reused `$E000` for tier payloads and invalidated the overlay, but `level_change_generate_current` still called post-generation special-room helpers that lived in the dungeon-generation overlay window.
- **Resolution:** After any C128 tier transition that can reclaim `$E000`, explicitly reload the required overlay before calling helpers that still execute from that window, and add a regression that proves the helper runs after the restore.
- **Rule:** **On C128, once a step like `tier_load` reuses `$E000`, assume overlay-resident helpers are dead until the overlay is explicitly reloaded.**
