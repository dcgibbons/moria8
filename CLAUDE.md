# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Port of the rogue-like game Moria to Commodore 64 and 128, written entirely in 6502 assembly using the Kick Assembler toolchain. Based on [umoria](https://github.com/dungeons-of-moria/umoria) (originally PASCAL on VAX/VMS).

## Build and Test

- **Build:** `make` (or `make build`) — assembles `main.s` → `out/moria.prg`
- **Run:** `make run` — build and launch in VICE
- **Test:** `make test` — assemble + run all tests in VICE headless
- **Disk image:** `make disk` — create a .d64 disk image
- **Clean:** `make clean` — remove build artifacts
- **Assembler:** Kick Assembler suite of tools (path override: `make KICKASS=/path/to/KickAss.jar`)
- **Testing:** Kick Assembler `.assert` directives (assembly-time) + VICE headless runtime tests
- **Entry point:** `main.s`

## Architecture

- **Display:** 40-column on C64; 40 or 80-column selectable on C128. PETSCII characters only (no bitmap graphics).
- **Loading:** BASIC stub loader runs the ML program. Cartridge version also supported. Minimize disk access after initial load — organize data so each dungeon level has what it needs in memory (e.g., higher-level monsters only loaded for deeper levels).
- **KERNAL/BASIC:** Use C64/C128 KERNAL routines freely. Do NOT use BASIC routines after the initial loader. Since BASIC is not active, its zero page space is available for program use.
- **Memory:** Use C64 memory banking to access RAM behind BASIC ROM for extra program space. Program should be able to exit cleanly back to BASIC.
- **Source organization:** Small, modular files each targeting a single piece of functionality.

## Coding Conventions

- Use canonical 6502 assembly conventions for Kick Assembler
- Every feature must have unit tests (`.assert` for compile-time, VICE headless for runtime)

## Test Bootstrap Requirement

Test files that grow past $A000 will **silently hang** in VICE. `BasicUpstart2(test_start)` generates a BASIC `SYS` to `test_start`, but at startup BASIC ROM is banked in at $A000-$BFFF. If `test_start` lands in that range, SYS jumps into ROM code instead of the test — causing an infinite loop / cycle-limit timeout with no error message.

**Fix:** Any test whose assembled code crosses $A000 must use the bootstrap trampoline pattern (see `test_item.s`): a small stub at $080E that banks out BASIC ROM first, then `jmp test_start`. `BasicUpstart2` points to the stub, not `test_start` directly. The "Test Code" segment label goes on the stub so `run_tests.sh` extracts the correct breakpoint address.

**How to check:** After assembling, look for `test_start` in the symbol file. If its address is >= $A000, the trampoline is required. Adding new `#import` lines (e.g., `reu.s`, `tier_manager.s`) can push `test_start` past $A000 without any other code changes.
