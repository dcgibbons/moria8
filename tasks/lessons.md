# Lessons Learned

Active playbook only. Keep this file short, durable, and reusable.
Move incident-specific postmortems and older detail into `tasks/lessons_archive.md`.

## Verification

- Treat the user's exact failing command or repro as the primary gate until it passes.
- Do not claim a fix from theory, partial tests, or neighboring evidence while the live gate is still red.
- For visual, boot, and interaction bugs, the user-visible path outranks synthetic harness evidence.
- Re-run the exact reported gate after each candidate fix before changing your conclusion about status.
- Once the fix is in, the relevant targeted gates are green, and independent tester signoff is green, stop; do not churn on redundant broad reruns after a transient harness hiccup unless the user explicitly asks for more proof.

## Regression Ownership

- If the user says a command or harness was green before your change and is now red, treat that as your regression until the exact command is green again.
- Do not dismiss new failures as harness noise until you have ruled out your own layout, build, or orchestration changes.
- If performance is part of the contract, do not close the bug with a slower fallback unless the user explicitly approves that tradeoff.

## Scope And Design

- When the user broadens a repro, redesign around the shared owner, not the first visible trigger or old bug label.
- When the user narrows a bug to one platform, stop assuming the shared path is primary; isolate the platform-owned seam with a targeted repro before widening the fix.
- When the user corrects a failing asset, overlay, or symbol name, re-anchor on that exact target before continuing; the wrong filename can point at a completely different owner and failure mode.
- For guided setup UX, trigger the flow at the first real operation that needs the resource, not earlier in the surrounding journey; forcing setup too early turns normal progression into a regression.
- On C64, a live hang with low-RAM PC values and repeated `IRQ -> $FFFF` is a banking-contract bug first: assume `$01=$35` leaked into an interrupt-driven input loop and harden the prompt/return seam before blaming disk I/O.
- On C64, treat title/UI re-entry as its own banking boundary: normalize back to `$01=$36`, restore the runtime IRQ wedge, and repair VIC bank state at the boundary itself instead of trusting each preceding KERNAL caller to leave UI code in a safe state.
- On 6502, never try to carry saved processor state across a `JSR`/`RTS` boundary on the hardware stack; if a helper must preserve flags across separate enter/exit routines, save them in explicit memory and rebuild `P` locally before return.
- On C64, if a new crash PC lands in the middle of a valid instruction after adding `PHA`/`PHP`-style bookkeeping around an interactive path, treat it as a stack-return regression first and prefer an existing scratch byte over carrying state on the stack across prompts.
- On C64, do not use `php/plp`-style wrappers around save/load entrypoints that need a carry result or a stable post-I/O bank state; normalize `$01` explicitly on return instead of restoring stale flags.
- On C64, do not reopen IRQs inside a disk/KERNAL helper that returns to overlay-owned UI state; let keyboard/input routines own their own IRQ window, but keep overlay disk-validation paths synchronous or you can turn screen writes into page-1 corruption.
- On C64, for overlay-driven disk validation paths, preserving only `$01` and flags is not enough; treat caller ZP/UI scratch as contaminated by KERNAL serial calls and restore it explicitly before returning to screen clear/print code.
- On C64, do not resume the same overlay frame after KERNAL disk I/O. Make the overlay disposable, keep it display/input-only, and move the disk state machine into resident or banked non-overlay code that re-enters the overlay fresh for each step.
- On C64, a redesign that removes disk I/O from the overlay is still not enough if multiple helpers each “restore enough state” locally. FEAT-DISK needs one authoritative owner of `$01`, interrupt policy, IRQ/editor legality, and stack assumptions across the full transaction, or the bug will keep moving between `$34`, `$36`, and `$37` contexts.
- When a C64 failure keeps moving between low-RAM crashes, IRQ-vector collapses, and KERNAL/editor returns, stop patching seams and instrument the full transaction first. Find the first illegal transition before making another behavioral fix.
- On this C64 layout, even debug-only diagnostics can violate hard ceilings. Before committing to in-code tracing, check whether the resident and banked segments have enough slack for the tracer itself; if they do not, shrink the diagnostic design first instead of forcing a larger “temporary” trace into the image.
- On C64, if a helper body lives in ROM-shadowed RAM (`$A000-$BFFF` or `$F000-$FFFF`), do not return to it directly from a KERNAL vector. Route the KERNAL call through an always-visible low-RAM trampoline or keep the whole helper on a substrate that stays executable across the call.
- On C64, if a FEAT-DISK read path leaves menus echoing typed characters or only accepting input after Return, assume KERNAL channel ownership leaked back into the screen editor. Do not split `CHKIN -> CHRIN -> CLRCHN` across generic wrappers; own the full read transaction in one low-RAM helper and resync the normal UI runtime on return.
- On this C64 build, adding a helper low in memory still grows the Default segment and can push both `program_end` and the banked-payload staging window over hard limits. Before choosing “low helper” as the fix shape, re-check the full segment ceilings rather than assuming low placement is free.
- For C64 FEAT-DISK init on an already formatted disk, prefer “create marker and read DOS status after close” over unconditional disk format. Save-disk initialization and whole-disk format are not the same operation.
- On C64 title/menu entry, if the first command key is ignored after redraw or FEAT-DISK return, treat it as stale keyboard-buffer ownership first. Drain/release the buffer at the title boundary instead of blaming the menu parser.
- On C128, if FEAT-DISK returns to gameplay but controls still appear dead and the monitor sits in `input_poll_key_event` / `cia_scan_petscii`, inspect the follow-up-key release contract before assuming the caller failed to unwind. View restoration and input re-arm are separate seams.
- On C128, a stable live PC inside `cia_scan_petscii` after a modal return usually means the raw scan latches were never re-neutralized, not that FEAT-DISK or redraw is still running. Reset `igk_last_sample` / `igk_stable` at the modal release seam before patching higher-level save flow again.
- When the same live trace persists across clean rebuilds, stop patching lower-level seams in place and reframe the subsystem ownership. Repeated scanner-seam tweaks on C128 were wasted motion once the real problem became “FEAT-DISK is modeled as a subroutine instead of a mode transition.”
- On C128, no overlay routine at `$E000-$EFFF` may continue executing across `EnterKernal()`. That MMU transition exposes KERNAL ROM over the same address range, so any post-call return into overlay code is a control-flow bug even if the bytes on disk are correct. Use the resident `w_*` KERNAL wrappers or move the helper off the overlay.
- On C128, a design fix still has to fit both resident ceilings at once: moving code out of the Default segment can solve the staged-source ceiling at `$E000`, but if that code lands in `RuntimeLowData` it can silently collide with the floor-item / ego-item low-RAM ownership at `$1A00`. Check both constraints before calling a redesign “memory-safe.”
- On C128, if a subsystem needs a stable non-overlay owner and neither Default nor `RuntimeLowData` can absorb it, use a dedicated runtime-loaded common-RAM PRG instead of forcing the code back into the overlay or bloating the staged source past `$E000`.
- On C128, do not treat the `w_*` KERNAL wrappers as a persistent file-I/O session API. Each wrapper does its own `EnterKernal/ExitKernal`, so stateful transactions like `SETNAM -> SETLFS -> OPEN -> CHKIN -> CHRIN...` must stay inside one continuous KERNAL window.
- On C128 FEAT-DISK, do not call marker initialization “successful” just because the write path returned. Use the same proven contract as C64: scratch, plain create, write, close, then immediately verify with `disk_marker_present`.
- On C64, do not use a side-effecting drive command like `I0` as a device-presence probe. Presence checks should be passive so they do not trigger false negatives or flash the wrong drive while probing.
- On C64, do not assume `c64_disk_call` preserves `X` or `Y` across a KERNAL call. It forwards the caller's registers into KERNAL, but on return only the accumulator/carry contract is reliable unless you explicitly save other registers yourself.
- On C64 UI code, `screen_put_char` expects screen codes, not raw PETSCII or arbitrary device bytes. If you surface DOS/channel diagnostics directly, convert them to display-safe screen codes or print them as hex instead of trusting the raw byte stream.
- When a selected-device setup branch correctly rejects the program disk, keep the user inside that same drive’s retry loop; do not bounce them back out to a broader menu or a different default drive.
- On C64, REU overlay fetch must preserve the caller’s interrupt state. An unconditional `cli` after DMA creates a live `$01=$34` IRQ window and will collapse into low-RAM/zero-vector crashes even if the overlay logic itself is correct.
- On C64 DOS, do not use `@` replace semantics as the primary save-disk marker-init path. The reliable FEAT-DISK flow is `scratch -> plain create -> write -> close -> verify readback`, with status-channel text used only for diagnostics.
- On this C64 FEAT-DISK path, a positive marker readback is the real success gate. Command-channel bytes can help explain a failure, but they are too drive-specific to be the UI truth if readback and runtime behavior disagree.
- Before patching a newly narrowed interaction bug, verify whether the shared command intentionally stops on visibility or ownership boundaries; an apparent platform-only failure may be the expected shared stop condition in a different live scene.
- If a symptom returns after a seam-specific fix, check sibling paths into the same subsystem before assuming the original fix was lost.
- For scan/classification bugs, verify every sibling data source at the seam before closing it; fixing item lookup alone is insufficient if stale monster lookup can still win on the same blocked tile.
- When the user changes the product target, stop optimizing the old architecture by inertia and restate the new target in the plan.
- When the user asks for a bounded action like “revert” or “build the test,” stop after that action and report the exact state; do not roll straight into debugging the next failure without explicit approval.
- Verify source-game geometry before extending or porting it; do not infer fixed subregion sizes like town from live dungeon dimensions or from older AI-written port code.
- When a fixed logical subregion lives inside a larger backing map, fix both halves of the contract: generation must make the out-of-region space non-presentational, and viewport math must clamp to the logical region rather than the backing buffer.

## C128 Contracts

- For C128 runtime-loaded or banked code, verify together: linked address, PRG load address, destination bank, visible execution bank, and copy-source safety.
- For C128 callable code, verify the full body and its required data stay out of `$D000-$DFFF`; an entrypoint below the I/O hole is not enough.
- When a C128 boot or chain path fails repeatedly, stop patching around symptoms and re-anchor on the proven loader and MMU/KERNAL contract.
- For 8563 VDC block operations, verify the register trigger contract byte-for-byte: mode/select registers must be programmed before the register write that starts the operation, and stale device state should be treated as part of the bug until disproven.

## Layout And Build Safety

- After assembly or import-order changes, re-check memory-map boundaries and treat new hangs or timeouts as likely layout regressions first.
- For disk images with patched boot sectors or reserved media, reserve the owned sector before file allocation.
- When a build or test depends on tool handoff, make fresh-build paths deterministic; do not rely on warm outputs or fragile temp-path behavior.

## C64 Banking And IRQ

- If a live C64 hang lands in low RAM with repeated `IRQ -> $FFFF` frames, inspect the `$01`/interrupt contract before chasing memory corruption; `$01=$35` with IRQs active means KERNAL vectors are banked out and prompt/input code likely returned in the wrong bank state.
