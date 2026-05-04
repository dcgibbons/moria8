# Lessons Learned

Active playbook only. Keep this file short, durable, and reusable.
Move incident-specific postmortems and older detail into `tasks/lessons_archive.md`.

## Operating Rules

- Treat the user's exact failing command, live repro, screenshot, or VICE snapshot as the primary gate until it passes. Theory, partial suites, helper-level tests, and neighboring smokes do not close a live bug.
- If the user says a repro is unchanged or a previously green gate regressed after your change, stop defending the current hypothesis. Re-anchor on the exact path, make the red command/repro explicit, and fix that regression first.
- Do not speculate about or name alternate ROMs in monitor-analysis explanations. Describe the observed KERNAL entry point, project call path, and product contract only.
- Before committing in a dirty worktree, audit every modified file and classify it as in-scope, out-of-scope, or user-owned. Commit only the intended scope.
- When the user asks for documentation or planning only, stop at the requested artifact. Do not start implementation without a separate go-ahead.
- For active doc cleanup, keep `tasks/todo.md` and `commodore/BUILDPLAN.md` active-only. Move completed or historical detail to `commodore/BUILDPLAN_HISTORY.md`, and use descriptive active IDs instead of opaque reused IDs like old `OPT-N` labels.

## Verification

- Prefer exact product-path automation for visual, boot, disk, save/load, title, and interaction bugs. Synthetic harnesses are diagnostics unless they reproduce the same user-visible contract.
- For disk initialization bugs, a mocked helper/unit test is not closure unless it writes to an actual attached disk image and verifies the resulting directory/file contents or product readback. Register-clobber tests are useful diagnostics, but they do not prove the live CBM DOS transaction.
- If a manual disk-init repro still fails, stop patching the helper in isolation. Preserve the snapshot as the gate, inspect the real DOS transaction/status, and add a product-path disk-image smoke before claiming the issue is fixed.
- A plausible C128 logical-file ownership fix is not closure for save-disk initialization. If the manual blank-disk init still shows "Could not initialize disk", stop adding ownership guesses and instrument the real marker transaction phase/status in the product path.
- If the expected marker file is absent from the disk, do not interpret readback bytes as stale file content. Treat the write/create transaction as failed until the directory shows the marker entry with verified contents.
- If a live product disk-init failure makes no progress after a proposed root-cause fix, promote the product snapshot and disk image to the only gate. Do not keep iterating on helper-level theories or mock-only tests until the failed live transaction explains where the write/open/status contract actually breaks.
- When fixing a one-opcode 6502 carry contract, diff the exact label block before running tests. A repeated `sec`/`clc` nearby can make an imprecise patch change the failure return instead of the success return.
- For multi-platform changes, verify each affected platform. A green C64 gate does not cover C128, and vice versa.
- Do not run exact C64 and C128 make gates in parallel; shared generated artifacts and VICE state can create false failures.
- For monitor-driven tests, capture the real stop condition and emulator stdout/stderr. A pass trap is the result; later cycle-limit noise after `BRK` is not a product JAM.
- If a test or harness talks to the VICE monitor on `127.0.0.1`, run it outside the sandbox when needed; sandboxed localhost failures are not product evidence.
- Do not run a platform build target in parallel with that same platform's smoke/test target. They share generated overlay/runtime files and can race into false missing-file failures.
- C128 unit runners must use one launch contract. If the Python harness monitor-loads PRGs and jumps to `test_start`, do not let the shell worker use ROM autostart for the same unit set; that creates divergent failures unrelated to the unit code.
- C128 performance measurement harnesses may observe product behavior, but must not define a new boot, load, bank, disk, or runtime execution contract. If sampling work starts producing runtime-load failures, stop and move the sample back onto the trusted product/test launch path.
- `xxd` takes an optional output filename as its second positional argument. Never pass multiple files to one `xxd` read command; inspect each file with a separate command so generated PRGs are not overwritten by a hexdump.

## Product Contracts

- User-facing text, filenames, and prompts are product contract. Do not shorten strings, display filenames, or visible copy to save bytes without explicit approval; recover space through ownership, layout, overlays, or deduplication first.
- When memory pressure appears in item/UI work, do not propose copy or display-name squeezing as an option; start with code ownership, overlay placement, and deduplication.
- Item consumption paths must defensively remove carried singleton records when `inv_qty` is `0` or `1`; decrementing a zero quantity underflows to `$ff` and duplicates the item into inventory plus floor/effect output.
- Stack consumption fixes need a visible inventory-count assertion too. If the item name hides `inv_qty`, the player cannot tell that arrows/bolts are being consumed until the stack disappears.
- Death/restart/menu prompts need hard source or rendered-output guards for exact copy. The C128 death prompt contract is `R)eboot S)tart Q)uit`; a lesson alone is not a control.
- Do not duplicate filename literals for load and display paths. User-visible preload names should point at the same source strings used for KERNAL `SETNAM`, with explicit load lengths when terminators differ.
- For filtered inventory prompts, visible letters are contiguous filtered entries, not raw carried slots. The prompt range, `?` overlay, and accepted letters must all use the same filtered cache.
- When an action changes a remote floor-visible object without moving the player, set the scene-redraw latch at the mutation site; correct item tables and map flags are not enough if the renderer can choose a local redraw.
- For glyph/rune or placement-spell bugs, assert the user-visible inspect/look/render path. Bookkeeping or generic non-wall messages are not sufficient proof.
- A visible C64 screen cannot coexist with generation scratch allocated in `$0400-$07ff`. If a progress screen must remain visible, remove the screen-RAM scratch owner; blanking the screen is only a behavior change, not a root-cause fix.

## C64 Contracts

- Treat new C64 hangs, low-RAM PCs, `IRQ -> $FFFF`, or crashes after layout/banking changes as banking/layout regressions first. Check `$01`, IRQ state, stack discipline, segment ceilings, and hard-coded buffers before blaming VICE or the harness.
- C64 overlay or banked code must preserve caller interrupt/bank contracts. Do not reopen IRQs while returning to `$01=$34/$35`, and do not resume an overlay frame after KERNAL disk I/O.
- Do not execute helper bodies from ROM-shadowed RAM after banking KERNAL/BASIC visible. Raw KERNAL transactions need always-visible low-RAM/resident code or a safe copied helper substrate.
- KERNAL-loaded product filenames must use explicit PETSCII/ASCII bytes when source encoding may be screen-code. A green unit suite is not enough for new product disk assets; run a product D64 smoke that actually loads the file from drive 8.
- C64 disk flows need one owner for `$01`, IRQ policy, KERNAL/editor legality, stack assumptions, logical file cleanup, and retry state. If failures move between low-RAM crashes, channel state, and UI echoes, instrument the full transaction before patching seams.
- C64 save/load and marker writes should use proven CBM DOS contracts: passive presence checks, explicit cleanup after failed opens, verified marker readback, and overwrite flows that match the product path.
- A product overlay routine must not call a modal/helper that loads a different overlay and then return without restoring its own overlay first. Base that decision on the immediate return address, not only `current_overlay`, because resident nested prompts can run while an overlay-owned command is still on the outer stack.
- When C64 code can run with KERNAL hidden, validate and reassert both bytes of the hidden-RAM IRQ/NMI vectors before enabling IRQs or returning from disk/overlay transitions. A stale high byte can vector into unrelated resident code even when the low byte looks plausible.
- Any C64 path that can fall through to KERNAL LOAD/SETNAM/SETLFS must explicitly bank KERNAL ROM visible first, even if a later epilogue reasserts hidden-RAM vectors. Vector hardening after the call does not protect a call that already entered RAM under KERNAL.
- When adding bank setup before a register-argument call, preserve the argument registers explicitly. `overlay_load_no_kernal` takes the overlay ID in `A`; clobbering `A` with a bank byte changes the requested overlay.
- When changing C64 input/banking restore order, audit the stack push order in the same edit. If flags are pushed above the saved bank byte, restoring the bank before `plp` requires pushing flags first or explicitly shuffling the saved bytes.

## C128 Contracts

- For C128 runtime-loaded, banked, copied, or trampolined code, verify linked address, PRG load header, destination bank, visible execution bank, callable body/data location, and copy-source safety together.
- If live C128 gameplay reports a JAM in `$D000-$DFFF`, map the exact PC to the latest symbol file and add or extend the residency audit for that callable before declaring the path fixed.
- On C128, a callable label below `$D000` is not enough. Audit the callable body/extent or move it behind a below-I/O trampoline if growth can execute into `$D000-$DFFF`.
- No C128 overlay routine at `$E000-$EFFF` may continue executing across `EnterKernal()`. Use resident `w_*` wrappers or move the helper off the overlay.
- C128 runtime and overlay assets must be loaded from program-media ownership, not `save_device`; save disks must not be allowed to satisfy program-file loads accidentally.
- C128 variant test disks must rewrite the whole variant-owned file set when resident/overlay contracts change. Replacing only `moria128` can silently mix incompatible assets.
- C128 multi-output assembler rules need one deterministic build owner for every emitted PRG. If `moria128.prg` is up to date but a split resident artifact is missing, disk creation must force the assembler owner instead of proceeding with stale/missing files.
- Preserve the user-visible preload sequence when moving resident/runtime load ownership. New runtime PRGs may need to load first, but `tier_init`/`Preloading files:` still belongs before title entry unless the product flow is intentionally redesigned.
- For C128 direct-scan input, keep physical-held-state, modifier filtering, stable-neutral latches, modal release reset, and PETSCII command decode as separate contracts.
- If a C128 runtime PRG takes over low common RAM that KERNAL previously used for its IRQ tail, `EnterKernal` must stop restoring the captured KERNAL tail before that LOAD begins. Otherwise later KERNAL disk I/O can IRQ into runtime payload bytes.
- C128 runtime-file loaders must use the resident `w_*`/`EnterKernal` wrappers. Raw `$FFxx` KERNAL calls bypass the vector/MMU ownership contract and can leave failures for the next file load to expose.
- C128 disk setup and marker validation are KERNAL/MMU-owned paths. Helpers that can be called from title/menu banking states must live below ROM-shadowed regions, and code outside that safe substrate must use resident `w_*` wrappers instead of keeping KERNAL/BASIC visible across the helper body.
- C128 multi-call KERNAL file transactions need one contiguous KERNAL ownership window when they depend on channel/file state across `SETNAM`/`SETLFS`/`OPEN`/`CHKIN`/`CHKOUT`/byte I/O/`CLOSE`. `w_*` wrappers are appropriate for isolated KERNAL calls, but splitting a file create/write sequence across wrapper enter/exit boundaries can lose live transaction state.
- When C128 disk diagnostics no longer fit in `128.fdisk`, create a named runtime/resident owner with explicit asserts instead of squeezing bytes into common RAM. Keep the product-path diagnostic symbols stable enough for monitor dumps.
- C128 logical file numbers are ownership too. When adding runtime-loaded PRGs, keep save-marker, save/load, score, command-channel, and runtime-loader logical file numbers disjoint, and add assembler asserts for the ranges.
- Any C128 KERNAL byte I/O call may clobber `A`, `X`, and `Y`. Disk marker/save/load loops must keep indexes in memory or explicitly preserve registers, and tests must deliberately clobber registers in mocked `CHRIN`/`CHROUT` paths.
- A drive command status like `"74"` is not a complete root cause by itself. If the user says the save disk is ready, instrument the preceding C128 disk transaction stages separately instead of reinterpreting readiness or collapsing init/scratch/write-close status into one byte pair.
- On C128 sequential reads, `READST=$40` after `CHRIN` can be a valid end-of-information indication for the byte just returned. Marker/read validators must compare the final expected byte before treating final-byte `$40` as failure; earlier `$40` is still a short read.
- On C128, `$0314/$0315` has two distinct owners: KERNAL mode needs the captured KERNAL software IRQ vector, while all-RAM runtime needs `mmu_common_irq`. Do not install the all-RAM hardware IRQ bridge as the KERNAL software IRQ vector.
- C128 preload file transactions must not reopen runtime IRQ windows between
  related KERNAL calls. If the live stack shows repeated `IRQ -> mmu_common_irq`
  during tier/overlay preload, defer runtime IRQ vector ownership until preload
  completes and mask interrupts for the whole `LOAD`/`CLOSE`/`CLRCHN`/SETBNK
  transaction.
- C128 common helper symbols are not proof that the helper bytes were copied
  into common RAM. If a common helper blob can grow past 256 bytes, the copy
  routine must copy full pages plus the tail and assert the supported blob
  bounds; otherwise valid symbols can jump into uncopied `BRK` space.
- C128 runtime PRG load failures must not jump back to `entry_main`; that restarts `tier_init` and presents a missing/mixed runtime file as an infinite monster/overlay reload loop.
- C128 boot-time calls into split resident domains must happen only after those resident PRGs are loaded. A symbol address in `128.world`/`128.item`/`128.select` is still filler bytes until the corresponding runtime file has been loaded.
- C128 direct runtime LOADs to `$F000` must not cross `$FF00`; `$FF00-$FF0F` is MMU/register ownership, not ordinary payload space. If the `$F000` resident payload grows too high, split a small callable runtime PRG into safe low RAM and audit its ownership explicitly.
- For C128 resident layout pressure, prefer domain-sized PRGs with hard owner bounds over many tiny payloads. If hot residents still cannot fit below `$D000`, move cold paths such as save/load behind an explicit modal broker instead of squeezing strings or drifting into the I/O hole.

## UI And Rendering

- The user-visible path outranks source-level plausibility. For modal/render corruption, assert while the target screen is still painted; post-dismiss checks are usually too weak.
- Shared C64/C128 UI code must emit display-safe bytes for both backends. Do not pass raw mixed-case screen-code or PETSCII assumptions through shared `screen_put_char` paths without tests.
- On C64, `screen_put_char` takes screen codes, not PETSCII/ASCII. Brackets are `$1B/$1D`, not `$5B/$5D`; punctuation constants in shared item/UI formatters need rendered-output or static guards.
- On C128 VDC, keep full-frame and single-tile overlay precedence in lockstep; glyphs/items/monsters/player must render consistently across redraw paths.
- For title/boot art, do not call a build green enough. Require a poster-validating runtime check, and preserve actual product composition before platform-specific hacks.

## Architecture And Scope

- Prefer root-cause ownership fixes over byte shaving. If a fix feels like trimming unrelated text or moving code just to fit, re-check the intended owner, substrate, and segment ceilings.
- When a product target changes, stop optimizing the old architecture by inertia. Restate the new target in docs and keep old-path spikes explicitly temporary.
- If a subsystem keeps failing through sibling paths, redesign around the shared owner rather than the first visible trigger or old bug label.
- For upstream parity questions, use the local source trees in `~/Projects/thirdparty/umoria` and `~/Projects/thirdparty/vms-moria` before browsing or inferring behavior.
- Do not use forced rebuilds (`make -B`) for analysis/audits unless the task truly requires rebuilding generated artifacts; forced builds can retrigger tool bootstrap/download paths and create unnecessary disruption.
- Before recommending an old save/load or title-load backlog item as next work, revalidate that it still describes a current product risk. Do not treat historical test-trust notes as active bugs after the user says the path is no longer relevant.
