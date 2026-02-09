# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Port of the rogue-like game Moria to Commodore 64 and 128, written entirely in 6502 assembly using the Kick Assembler toolchain. Based on [umoria](https://github.com/dungeons-of-moria/umoria) (originally PASCAL on VAX/VMS).

## Build and Test

- **Assembler:** Kick Assembler suite of tools
- **Testing:** Kick Assembler `.assert` directives (assembly-time) + VICE headless runtime tests (`x64sc -console -nativemonitor`)
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
