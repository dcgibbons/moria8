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
