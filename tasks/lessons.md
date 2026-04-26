# Lessons Learned

Active playbook only. Keep this file short, durable, and reusable.
Move incident-specific postmortems and older detail into `tasks/lessons_archive.md`.

## Operating Rules

- Treat the user's exact failing command, live repro, screenshot, or VICE snapshot as the primary gate until it passes. Theory, partial suites, helper-level tests, and neighboring smokes do not close a live bug.
- If the user says a repro is unchanged or a previously green gate regressed after your change, stop defending the current hypothesis. Re-anchor on the exact path, make the red command/repro explicit, and fix that regression first.
- Before committing in a dirty worktree, audit every modified file and classify it as in-scope, out-of-scope, or user-owned. Commit only the intended scope.
- When the user asks for documentation or planning only, stop at the requested artifact. Do not start implementation without a separate go-ahead.
- For active doc cleanup, keep `tasks/todo.md` and `commodore/BUILDPLAN.md` active-only. Move completed or historical detail to `commodore/BUILDPLAN_HISTORY.md`, and use descriptive active IDs instead of opaque reused IDs like old `OPT-N` labels.

## Verification

- Prefer exact product-path automation for visual, boot, disk, save/load, title, and interaction bugs. Synthetic harnesses are diagnostics unless they reproduce the same user-visible contract.
- For multi-platform changes, verify each affected platform. A green C64 gate does not cover C128, and vice versa.
- Do not run exact C64 and C128 make gates in parallel; shared generated artifacts and VICE state can create false failures.
- For monitor-driven tests, capture the real stop condition and emulator stdout/stderr. A pass trap is the result; later cycle-limit noise after `BRK` is not a product JAM.
- If a test or harness talks to the VICE monitor on `127.0.0.1`, run it outside the sandbox when needed; sandboxed localhost failures are not product evidence.

## Product Contracts

- User-facing text, filenames, and prompts are product contract. Do not shorten strings, display filenames, or visible copy to save bytes without explicit approval; recover space through ownership, layout, overlays, or deduplication first.
- Do not duplicate filename literals for load and display paths. User-visible preload names should point at the same source strings used for KERNAL `SETNAM`, with explicit load lengths when terminators differ.
- For filtered inventory prompts, visible letters are contiguous filtered entries, not raw carried slots. The prompt range, `?` overlay, and accepted letters must all use the same filtered cache.
- When an action changes a remote floor-visible object without moving the player, set the scene-redraw latch at the mutation site; correct item tables and map flags are not enough if the renderer can choose a local redraw.
- For glyph/rune or placement-spell bugs, assert the user-visible inspect/look/render path. Bookkeeping or generic non-wall messages are not sufficient proof.

## C64 Contracts

- Treat new C64 hangs, low-RAM PCs, `IRQ -> $FFFF`, or crashes after layout/banking changes as banking/layout regressions first. Check `$01`, IRQ state, stack discipline, segment ceilings, and hard-coded buffers before blaming VICE or the harness.
- C64 overlay or banked code must preserve caller interrupt/bank contracts. Do not reopen IRQs while returning to `$01=$34/$35`, and do not resume an overlay frame after KERNAL disk I/O.
- Do not execute helper bodies from ROM-shadowed RAM after banking KERNAL/BASIC visible. Raw KERNAL transactions need always-visible low-RAM/resident code or a safe copied helper substrate.
- C64 disk flows need one owner for `$01`, IRQ policy, KERNAL/editor legality, stack assumptions, logical file cleanup, and retry state. If failures move between low-RAM crashes, channel state, and UI echoes, instrument the full transaction before patching seams.
- C64 save/load and marker writes should use proven CBM DOS contracts: passive presence checks, explicit cleanup after failed opens, verified marker readback, and overwrite flows that match the product path.

## C128 Contracts

- For C128 runtime-loaded, banked, copied, or trampolined code, verify linked address, PRG load header, destination bank, visible execution bank, callable body/data location, and copy-source safety together.
- No C128 overlay routine at `$E000-$EFFF` may continue executing across `EnterKernal()`. Use resident `w_*` wrappers or move the helper off the overlay.
- C128 runtime and overlay assets must be loaded from program-media ownership, not `save_device`; save disks must not be allowed to satisfy program-file loads accidentally.
- C128 variant test disks must rewrite the whole variant-owned file set when resident/overlay contracts change. Replacing only `moria128` can silently mix incompatible assets.
- For C128 direct-scan input, keep physical-held-state, modifier filtering, stable-neutral latches, modal release reset, and PETSCII command decode as separate contracts.

## UI And Rendering

- The user-visible path outranks source-level plausibility. For modal/render corruption, assert while the target screen is still painted; post-dismiss checks are usually too weak.
- Shared C64/C128 UI code must emit display-safe bytes for both backends. Do not pass raw mixed-case screen-code or PETSCII assumptions through shared `screen_put_char` paths without tests.
- On C128 VDC, keep full-frame and single-tile overlay precedence in lockstep; glyphs/items/monsters/player must render consistently across redraw paths.
- For title/boot art, do not call a build green enough. Require a poster-validating runtime check, and preserve actual product composition before platform-specific hacks.

## Architecture And Scope

- Prefer root-cause ownership fixes over byte shaving. If a fix feels like trimming unrelated text or moving code just to fit, re-check the intended owner, substrate, and segment ceilings.
- When a product target changes, stop optimizing the old architecture by inertia. Restate the new target in docs and keep old-path spikes explicitly temporary.
- If a subsystem keeps failing through sibling paths, redesign around the shared owner rather than the first visible trigger or old bug label.
- For upstream parity questions, use the local source trees in `~/Projects/thirdparty/umoria` and `~/Projects/thirdparty/vms-moria` before browsing or inferring behavior.
