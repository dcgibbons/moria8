# C128 Overlay / Preload Retrospective

## Summary

The long-running C128 `New Game` crash was not one bug. It was a chain of two
different failure families introduced after the port moved from disk-only loads
to the newer overlay + preload/cache model:

1. Overlay execution and banked-payload reload were allowed to share the same
   live Bank 0 window.
2. After that overlap was repaired, the remaining failure narrowed to the
   C128 preload `LOAD` transaction itself.

The key lesson is that C128 stability depends on **explicit memory ownership**
and **one authoritative KERNAL I/O path**. Once either of those contracts is
violated, the crash addresses become noisy and misleading.

## What Was Broken

### 1. Startup overlay and banked payload overlapped

The original regression came from letting these two lifetimes share one live
execution region:

- `$E000-$EFFF` startup overlay execution
- banked payload reload destination in the same Bank 0 window

That created self-overwrite scenarios:

- startup overlay code pushed a valid return address
- `init_copy_banked` recopied a different payload over those bytes
- the CPU returned into overwritten code or adjacent data

This is why the original failures moved around so much:

- `$4D00`-range Huffman data execution
- `$E005`-style returns into data just after a safe-zone wrapper
- later stack-collapse signatures

Those changing PCs were not separate bugs. They were symptoms of one unstable
execution model.

### 2. The character sheet path amplified the overlap

`ui_char_display` lived in the reloadable banked window while startup overlay
code still called into that path. That created an especially bad case:

- startup overlay called into a trampoline
- trampoline recopied banked payload
- overlay return address pointed back into bytes that no longer held overlay code

The eventual fix was architectural, not local:

- startup overlays remain in `$E000-$EFFF`
- reloadable banked payload lives at `$F000-$FFFA`
- summary/UI work happens after overlay code has returned to resident code

### 3. Overlay metadata corruption was partly diagnostic self-interference

Later in the investigation, overlay filename/state bytes appeared corrupted.
That turned out to be a mix of two problems:

- the state block itself was living in a contested area
- some diagnostics were clobbering `A` or `X` while trying to observe them

Once the overlay state moved into the resident cache-state block and the guard
code preserved registers, the metadata proved healthy and the remaining failure
narrowed to the real C128 preload path.

## What Was Disproved

Several plausible theories were ruled out and should stay ruled out unless a
future build produces new evidence:

- `player_init`
- race/class/name/gender selection
- background text buffer adjacency
- `create_gen_background`
- `create_init_character`
- broad “town loop” corruption as the original trigger

These paths were useful to test because they helped isolate the crash, but they
were not the main architectural failure.

## Current State After The Repair

The original overlap bug family is materially fixed:

- `New Game` now survives full character creation and the summary path
- callable banked UI/runtime code is no longer reloaded into the startup overlay slot
- overlay metadata/state now lives in resident main RAM instead of adjacent to
  overlay code/data

The next remaining failure is healthier and easier to reason about:

- the request to load `OVL.START` is now confirmed correct
- the filename pointer/length are correct
- the target load address is correct
- the remaining failure is a real C128 KERNAL `LOAD` error in the preload path

That is a normal API-contract bug, not a “CPU returned into data” architecture
bug.

## Permanent Design Rules

### Memory ownership

- `$E000-$EFFF` is the overlay execution window only.
- `$F000-$FFFA` is the reloadable banked payload window only.
- Overlay metadata/state must live in resident Bank 0 RAM.
- No startup-overlay code may trigger a banked payload recopy into Bank 0.

### Loader contract

- C128 preload filename data must live in resident Bank 0 RAM.
- `SETNAM`, `SETLFS`, `SETBNK`, `LOAD`, `CLOSE`, and `CLRCHN` must use the
  known-good C128-safe wrapper path.
- Do not maintain a second custom KERNAL transaction if a wrapper path already
  exists and is known to work.

### Diagnostic discipline

- Diagnostics must preserve observed registers by default.
- Any diagnostic that intentionally changes `A/X/Y/P` must say so explicitly.
- Heavy diagnostics that distort layout or timing should stay incident-scoped
  and not become permanent architecture.

## Guardrails That Should Remain

- Compile-time asserts that startup overlays and banked payload windows do not overlap
- Compile-time asserts that callable banked C128 code stays above the overlay window
- Debug-only `init_copy_banked` guard that traps if startup overlay execution is active
- Debug-only overlay filename/state integrity guard, provided it preserves registers
- A preload transaction snapshot block for future C128 load failures

## Regression Policy

Any future C128 change touching:

- overlay layout
- `init_copy_banked`
- banked payload placement
- C128 KERNAL wrappers or preload I/O

must re-run these checks:

1. `N` from title through summary, town entry, and first command
2. `N` twice in one session
3. at least one overlay transition after gameplay begins
4. banked UI screens after town entry

## Why This Needs To Be Preserved

This failure cost so much time because the symptoms were unstable:

- return addresses were valid when pushed and invalid when popped
- the CPU kept executing data instead of code
- tiny layout changes moved the crash and made false theories look plausible

The most important takeaway is simple:

**When a C128 bug produces moving `JAM` addresses, first suspect broken memory
ownership, not the currently executing function.**
