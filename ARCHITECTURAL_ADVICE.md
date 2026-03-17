# Architectural Review: C128 KERNAL-to-Game Boundary Stability

## 1. Executive Summary
The project is currently suffering from a "Porous Boundary" failure between the C128 KERNAL and the Game's "All-RAM" execution model. The recent `BREAK at E2A43` ($2A43) is a **Diagnostic Trap (Stage 43)** triggered during `title_screen.s` before a `kernal_load` operation. This trap indicates that **Stack Guards or Canaries at $3F00** were clobbered by a preceding operation.

## 2. Root Cause: Whack-a-Mole Dynamics
The current "Point-Fix" strategy (mirroring vectors, atomic `ExitKernal`) is insufficient because the KERNAL and the Game are competing for the same Zero Page and low-RAM workspace. Specifically:
- **Workspace Overlap:** The C128 KERNAL uses significant RAM below $4000 for disk I/O, RS-232, and editor state. When the game banks out the KERNAL, the hardware IRQ vectors still fire. If they fire into a "scrubbed" bank or a bank where the game has placed its own variables, corruption is inevitable.
- **Top Common RAM Sabotage:** The system relies on `$D506` toggling. If an interrupt fires during the transition, the CPU fetches vectors from a volatile bank.

## 3. Systemic Architectural Advice (for the Implementor)

To resolve this permanently, the implementor MUST move from "Bit-Flipping" to **"Boundary Encapsulation"**:

### A. The Common RAM Vector Bridge (Mandatory)
- **Eliminate Vector Volatility:** Move the Hardware IRQ/NMI/RESET vectors ($FFFA-$FFFF) to **Top Common RAM**.
- **The Bank-Agnostic Dispatcher:** Implement a trampoline in **Bottom Common RAM ($0C00 range)** that handles ALL interrupts. This trampoline must:
  1. Save the current MMU state (`$FF00`, `$D506`, `$01`).
  2. Switch to a known-good "Game Bank" (Bank 0).
  3. Execute the handler.
  4. Restore the exact MMU state before `RTI`.

### B. Workspace Quarantine
- **Move Statics:** Relocate `MMU_SAVE_*` and `KERNAL_NESTING_DEPTH` into **Page 1 ($0100-$01FF)** or a dedicated, unscrubbed block in **Common RAM**.
- **Seal the Zero Page:** Identify the exact ZP range used by the game ($02-$8F) and the KERNAL ($90-$FF). Ensure that **no game logic or data** ever touches the KERNAL's range, and that `EnterKernal` performs a **full atomic swap** of the game's ZP into a safe buffer.

### C. Hardened LOAD/SAVE Boundary
- **Pre-load Sanitization:** Before any KERNAL `LOAD` or `SAVE`, the game must fully "yield" the machine. This means:
  1. Disabling all custom IRQs.
  2. Restoring `$D506=$05` (Bottom Only, KERNAL ROM visible).
  3. Restoring `$01=$37` (Standard KERNAL/BASIC map).
  4. Only after the `LOAD` completes, performing a **Cold Re-assertion** of the Game's All-RAM invariants.

## 4. Immediate Investigative Task
The implementor should use a VICE memory-write-breakpoint (`watch store 3f00`) to identify exactly which instruction in the KERNAL or the Game is clobbering the canaries.
