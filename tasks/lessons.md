# Lessons Learned

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
- **Root Cause:** `viewport_update` / `render_viewport` were linked at low RAM `$1000`, `bank1.dat` had no real Stage 2 runtime loader, and the initial repair loaded it into **Bank 1** even though normal gameplay runs in `MMU_ALL_RAM` (**Bank 0**) and `$1000-$3FFF` is not bottom common RAM. The callsite was correct; the residency assumption was wrong.
- **Resolution:** Prove the execution context first: identify the visible bank at the callsite, confirm whether the target address is common or bank-private, then make the loader/header match that execution model. In this case, `bank1.dat` needed a `$1000` PRG header and a startup loader into **Bank 0** low RAM, not Bank 1.
- **Rule:** **For any callable low-RAM segment on C128, verify all three together before patching: (1) symbol address, (2) visible bank at the callsite, and (3) common-vs-private RAM ownership.** Never infer one from the others.

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
