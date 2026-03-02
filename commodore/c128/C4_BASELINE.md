# C4 Baseline Snapshot (2026-03-01)

## 1. Memory Layout (Current Failing State)

| Region | Start | End | Size | Notes |
|--------|-------|-----|------|-------|
| VIC-II / Scratch | $0400 | $09FF | 1536 | Used for BFS queue ($0400) |
| Screen Editor Workspace | $0A00 | $0AFF | 256 | RESERVED |
| **Dungeon Map** | **$0B00** | **$19FF** | **3840** | **MAP_SIZE = 80x48** |
| Floor Items | $1A00 | $1AFF | 256 | |
| Creature Scratch | $1B00 | $1BFF | 256 | RLE, hiscore |
| BASIC Stub | $1C01 | $1C0C | 12 | SYS 7182 ($1C0E) |
| **Main Program** | **$1C0E** | **$DEAB** | **49821** | Grows upwards |
| Banked Payload (Stored) | $CC79 | $DEAC | 4659 | Copied to $EB00 |
| Overlays (Runtime) | $E000 | $EFFF | 4096 | Shared segment |

## 2. Identified Risks and Failures

1. **Zero Safety Margin**: There are only 2 bytes ($1C00, $1C0D) of padding between the Creature Scratch area ($1B00-$1BFF) and the Main Program ($1C0E).
2. **Expansion Blocker**: Any increase in Map Size, Floor Items, or Creature Scratch will immediately overwrite the program entry point or the BASIC stub.
3. **Corruption Potential**: The Creature Scratch area is used for Huffman RLE decoding and high-score processing. If these buffers exceed 256 bytes, they will corrupt the program.
4. **Bootloader fragility**: The bootloader must ensure the program is loaded at exactly $1C01.

## 3. Crash Signatures (Reported)

- **Symptom A**: Program hangs at startup (BASIC stub corrupted by map clear or data load).
- **Symptom B**: Random crashes during dungeon generation (Map clear or generation logic writes into program space).
- **Symptom C**: "Jammed" VICE emulator (Infinite loop due to code corruption).

## 4. Test Baseline

- **C128 Tests**: NONE (C4.1 will add these).
- **C64 Tests**: 321 passing, but these do not cover C128-specific banking or VDC rendering.
- **Build Status**: `make -C commodore/c128 build128` passes (compiles), but the resulting binary is on the edge of failure.

## 5. Goal of C4

Relocate the Map to Bank 1 at $4000. This frees 3840 bytes in Bank 0, providing a significant safety margin and allowing for future map expansion (Phase 10.3).
