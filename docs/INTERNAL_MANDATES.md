# Internal Mandates

This file preserves durable engineering and hardware invariants for Moria8. It
is intentionally limited to rules that protect the source tree and runtime
architecture.

## Repository Hygiene

- Do not commit credentials, secrets, private environment files, generated
  build outputs, VICE snapshots, downloaded toolchains, or monitor logs.
- Do not stage or commit changes unless explicitly requested.
- Keep public documentation free of local machine paths and private process
  notes.

## User-Facing Text

Player-visible strings are product data. Do not shorten, rename, truncate, or
otherwise degrade prompts, menu labels, spell feedback, disk filenames, loading
lists, status messages, or error text merely to recover bytes.

When memory pressure appears, first recover space from ownership, overlays,
deduplication, dead code, or data layout. Only change player text for a real
product reason, and verify the rendered path on the affected target.

## Memory Boundaries

- C64 main segment must end below `$C000`.
- C128 main/default segment must end below its asserted runtime ceiling.
- The C64 map owns `$C000-$CEFF`; the C64 floor-item table owns `$CF00-$CFFF`.
- `$D000-$DFFF` is the I/O hole when I/O is visible and must not receive normal
  executable code or ordinary runtime payload data.
- Banked payloads must end below CPU vectors.
- Each overlay segment must fit in `$E000-$EFFF`.
- Test code entered directly through BASIC must start below `$A000`, or use a
  bootstrap trampoline that banks out BASIC ROM first.

After import reordering, segment movement, banking changes, or runtime payload
layout changes, rebuild and inspect the assembler memory map and `.print`
output. Existing boundary `.assert` statements are part of the contract; fix
the layout when they fail.

## Zero Page And KERNAL

- `$02-$8F` is game-owned only under the project's documented caller-save
  discipline.
- KERNAL routines clobber some low zero-page locations, including LOAD/SAVE and
  OPEN scratch locations. Long-lived game state must not rely on those bytes
  across KERNAL calls without save/restore.
- `$90-$FF` is KERNAL-volatile unless a specific platform file proves otherwise.

## C128 Banking

- Do not modify `$FF00` or processor port banking state without an atomic
  interrupt-safe sequence or a context-aware restore.
- Use established KERNAL entry/exit helpers for KERNAL calls.
- Keep `$D506` common RAM configuration at the documented 4 KB bottom/top common
  model unless the architecture and all assertions are redesigned together.
- Hardware vectors must point to common RAM or a validated vector bridge.
- Bank 1 ownership must follow `commodore/c128/memory128.s`; unassigned RAM is
  not free until an ownership entry and overlap assertions are added.
- `$1000-$3FFF` is bank-private in the shipping C128 runtime.
- `$D000-$DFFF` is not high RAM to borrow while I/O is visible.

## C128 Runtime-Loaded Code

For copied, disk-loaded, banked, recopied, or trampolined C128 code, verify:

1. linked symbol address
2. PRG load header
3. destination bank at load time
4. visible bank at execution time
5. staged source-span survival

Moving crash addresses usually indicate an ownership or visibility mismatch.
Re-check the full contract before patching local logic near the newest crash.

## Shared Code

- Shared entity data should remain struct-of-arrays.
- Use the existing math library for 16-bit arithmetic.
- Use the project RNG rather than ad hoc hardware reads.
- Shared `commodore/common/` changes that affect platform-conditional code must
  be verified on both C64 and C128.

## Verification

- Bug fixes should be backed by a failing reproduction or test where practical.
- Reported failing commands become the active gate until that exact command
  passes.
- For C128 work, prefer `make test128-fast` for unit iteration and
  `make test128-fast-smoke` for fast runtime smoke coverage. Use `make test128`
  before signing off broad banking, loader, overlay, or MMU changes.
- Headless VICE tests should use warp mode and should not rely on timeouts over
  30 seconds.
