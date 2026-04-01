# Lessons Learned

Active playbook only. Keep this file short, durable, and reusable.
Move incident-specific postmortems and older detail into `tasks/lessons_archive.md`.

## Verification

- Treat the user's exact failing command or repro as the primary gate until it passes.
- Do not claim a fix from theory, partial tests, or neighboring evidence while the live gate is still red.
- For visual, boot, and interaction bugs, the user-visible path outranks synthetic harness evidence.
- Re-run the exact reported gate after each candidate fix before changing your conclusion about status.

## Regression Ownership

- If the user says a command or harness was green before your change and is now red, treat that as your regression until the exact command is green again.
- Do not dismiss new failures as harness noise until you have ruled out your own layout, build, or orchestration changes.
- If performance is part of the contract, do not close the bug with a slower fallback unless the user explicitly approves that tradeoff.

## Scope And Design

- When the user broadens a repro, redesign around the shared owner, not the first visible trigger or old bug label.
- If a symptom returns after a seam-specific fix, check sibling paths into the same subsystem before assuming the original fix was lost.
- When the user changes the product target, stop optimizing the old architecture by inertia and restate the new target in the plan.
- When the user asks for a bounded action like “revert” or “build the test,” stop after that action and report the exact state; do not roll straight into debugging the next failure without explicit approval.

## C128 Contracts

- For C128 runtime-loaded or banked code, verify together: linked address, PRG load address, destination bank, visible execution bank, and copy-source safety.
- For C128 callable code, verify the full body and its required data stay out of `$D000-$DFFF`; an entrypoint below the I/O hole is not enough.
- When a C128 boot or chain path fails repeatedly, stop patching around symptoms and re-anchor on the proven loader and MMU/KERNAL contract.

## Layout And Build Safety

- After assembly or import-order changes, re-check memory-map boundaries and treat new hangs or timeouts as likely layout regressions first.
- For disk images with patched boot sectors or reserved media, reserve the owned sector before file allocation.
- When a build or test depends on tool handoff, make fresh-build paths deterministic; do not rely on warm outputs or fragile temp-path behavior.
