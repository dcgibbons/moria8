# Commodore HAL Restructure Plan

This document is the working checklist for turning the current C64/C128/Plus/4
Commodore tree into a real platform/HAL split. It complements
`docs/CROSS_PLATFORM_STRATEGY.md`; it does not replace the longer-term
top-level `core/` and `platforms/` migration plan.

The immediate goal is to stop treating the Plus/4 as a slightly modified C64
port. Common code should express game intent. C64, C128, and Plus/4 platform
code should own hardware execution.

## Current Failure Context

- [x] Plus/4 disk setup/save/load has one manual success pass after commit
      `bd43365 Fix Plus/4 save disk marker validation`.
- [x] Plus/4 disk setup/save/load is covered by automated
      runtime gates. `make testplus4-runtime` now covers marker initialization
      directly and a scripted product Disk Setup success path against a freshly
      formatted drive-9 save disk, the missing drive-9 save-media failure
      path, product save-write, and product load-resume from a generated
      Plus/4 save fixture.
- [ ] `make testplus4` is currently only an assembly/build artifact gate;
      `make testplus4-runtime` has minimal runtime and marker-init storage
      smokes.
- [ ] Manual screenshots and VICE monitor traces are diagnostic evidence, not
      release gates.
- [x] Resolved Plus/4 disk failure: `Disk code $00 phase $83` during save disk
      initialization/readback. Root cause was Plus/4 KERNAL calls clobbering
      `X` while marker read/write loops used `X` as the persistent marker
      index.
- [ ] Previous Plus/4 failures included C64 leakage through `$01` banking,
      `$dd00` VIC/CIA assumptions, raw KERNAL calls, hidden filename buffers,
      IRQ state drift, TED color mapping, and input repeat/release behavior.

## Current HAL Position

- [x] HAL contract skeleton exists in `commodore/hal/`.
- [x] Platform HAL placeholder directories exist for C64, C128, and Plus/4.
- [x] Static HAL boundary audit exists and passes against the current
      allowlist.
- [x] Storage HAL adapter labels exist for C64, C128, and Plus/4 and are
      checked by `tools/check_hal_storage_exports.py`.
- [x] Plus/4 storage has been stabilized enough for manual disk initialize,
      save, and load.
- [ ] Storage is still the highest-risk platform boundary because common code
      and platform code still share too much disk state, filename policy,
      logical file policy, status reporting, and platform-specific KERNAL
      assumptions.
- [x] Plus/4 resident space was reclaimed by replacing the linked C64 REU
      implementation with a Plus/4-owned no-REU stub. The product build now
      fits below `MAP_BASE`.
- [x] Current concrete HAL step completed: save-write/load-resume runtime gates
      are enabled before migrating more storage behavior out of common code.

## Target Directory Structure

Use this structure inside the current `commodore/` tree first. Do not start
with the larger top-level filesystem migration.

```text
commodore/
├── common/
│   ├── game/                 # Pure game rules and state logic
│   ├── ui/                   # UI intent/render-independent flows
│   ├── data/                 # Shared game data, strings, tables
│   └── compat/               # Temporary migration shims only
│
├── hal/
│   ├── hal_contract.s        # Required HAL imports / shared constants
│   ├── hal_lifecycle.s
│   ├── hal_memory.s
│   ├── hal_irq.s
│   ├── hal_screen.s
│   ├── hal_input.s
│   ├── hal_sound.s
│   ├── hal_storage.s
│   ├── hal_overlay.s
│   └── hal_audit.md
│
├── c64/
│   ├── main.s
│   ├── hal/
│   │   ├── lifecycle.s
│   │   ├── memory.s
│   │   ├── irq.s
│   │   ├── screen.s
│   │   ├── input.s
│   │   ├── sound.s
│   │   ├── storage.s
│   │   ├── overlay.s
│   │   └── layout.s
│   └── tests/
│
├── c128/
│   ├── main.s
│   ├── hal/
│   │   ├── lifecycle.s
│   │   ├── memory.s
│   │   ├── irq.s
│   │   ├── screen_vdc.s
│   │   ├── input.s
│   │   ├── sound.s
│   │   ├── storage.s
│   │   ├── overlay.s
│   │   └── layout.s
│   └── tests/
│
├── plus4/
│   ├── main.s
│   ├── hal/
│   │   ├── lifecycle.s
│   │   ├── memory.s
│   │   ├── irq.s
│   │   ├── screen_ted.s
│   │   ├── input_ted.s
│   │   ├── sound_ted.s
│   │   ├── storage.s
│   │   ├── overlay.s
│   │   └── layout.s
│   └── tests/
│
└── tools/
    ├── check_hal_boundaries.py
    └── disk_manifest_check.py
```

Longer term, after the Commodore HAL is stable, this can move toward:

```text
core/
platforms/commodore/{hal,c64,c128,plus4}
data/
tools/
```

## HAL Boundary Rules

- [ ] `commodore/hal/` contains contracts only. It must not contain hardware
      register writes, KERNAL mechanics, drive-specific behavior, or platform
      branching.
- [ ] `commodore/common/` owns game rules, map/entity/item/player state, turn
      sequencing, UI intent, storage intent, sound intent, and overlay intent.
- [ ] Platform directories own hardware execution: display, color, input,
      sound, ROM/RAM banking, IRQs, KERNAL entry/exit, overlay loading, disk
      setup, and save/load media behavior.
- [ ] Common code must not know whether a target uses VIC-II, VDC, TED, SID,
      CIA, MMU, `$01`, `$dd00`, `$ff3e/$ff3f`, 1541, 1551, or another drive.
- [ ] The HAL is compile-time/direct-call assembly. Do not use per-character
      dynamic dispatch in hot paths.
- [ ] Platform hot loops stay platform-owned: C64 direct screen/color RAM,
      C128 VDC register sequences, Plus/4 TED screen/attribute writes.

## HAL Service Contracts

Every HAL service must document:

- [ ] Input registers.
- [ ] Output registers.
- [ ] Clobbered registers and zero-page bytes.
- [ ] Carry/error convention.
- [ ] IRQ state on entry and return.
- [ ] ROM/RAM visibility on entry and return.
- [ ] Whether KERNAL/OS may be visible during the call.
- [ ] Required residency constraints for code and buffers.

Required services:

- [ ] Lifecycle: `platform_init_early`, `platform_init_runtime`,
      `platform_runtime_resync`, `platform_shutdown`, `platform_panic`.
- [ ] Memory/banking: enter OS, exit OS, enter all-RAM runtime, restore runtime
      bank, read/write/copy helpers.
- [ ] IRQ/timer: install runtime vectors, restore OS vectors, mask/unmask,
      acknowledge sources, critical sections, entropy/timing.
- [ ] Screen/color: init, clear, clear row, put char, put string, put char at,
      set logical color, blank/unblank, flash, begin/end bulk render.
- [ ] Input: get key, get command, get text char, wait release, any key held,
      run-cancel check, modal input prepare/finish.
- [ ] Sound: init, play semantic SFX ID, stop, update.
- [ ] Overlay/assets: load logical overlay/asset IDs, verify destination and
      post-load runtime state.
- [ ] Storage: probe media, require program/save media, open/read/write/close,
      read/write block, command/status handling, save/load record operations.
- [ ] Capabilities/layout: screen dimensions, viewport, message/status rows,
      overlay windows, OS-visible buffer spans, forbidden spans.

## Testable Units

### Pure Common Logic

- [ ] RNG algorithm, excluding hardware entropy.
- [ ] Math helpers.
- [ ] Item generation and item tables.
- [ ] Player stat/recalc logic.
- [ ] Inventory/equipment rules.
- [ ] Combat damage calculations.
- [ ] Monster AI decisions.
- [ ] Dungeon generation data invariants.
- [ ] Save-format encode/decode semantics, excluding disk I/O.
- [ ] Command dispatch from normalized `CMD_*`.
- [ ] Render-independent layout intent.

### HAL Contract Units

- [ ] `hal_lifecycle`: runtime state initialized, screen mode set, IRQ policy
      valid.
- [ ] `hal_memory`: OS entry/exit returns to documented runtime banking and
      preserves documented registers/flags.
- [ ] `hal_irq`: vectors installed, IRQs acknowledged, KERNAL calls do not
      leave runtime IRQ state wrong.
- [ ] `hal_screen`: clear, put char, put string, color mapping, row/column
      bounds.
- [ ] `hal_input`: key normalization, text input, key release/debounce,
      command mapping.
- [ ] `hal_sound`: play/stop named effects without stuck tones.
- [ ] `hal_overlay`: each overlay loads to the expected address and signature.
- [ ] `hal_storage`: media probe, open/read/write/close, normalized errors.

### Integration Slices

- [ ] Boot to title.
- [ ] Title screen render.
- [ ] New character creation.
- [ ] Enter town.
- [ ] Enter dungeon.
- [ ] Inventory/equipment/help overlays.
- [ ] Every overlay loads.
- [ ] Command loop accepts movement/action keys.
- [ ] Disk setup flow.
- [ ] Save write.
- [ ] Load resume.
- [ ] Disk error reporting.
- [ ] Quit/exit cleanup.

### Static/Build-Time Units

- [x] Common-code forbidden-symbol audit.
- [ ] Platform layout assertions.
- [ ] OS-visible filename/command/transfer buffer assertions.
- [ ] Disk image manifest checks.
- [ ] HAL completeness check: every platform exports required labels.
- [ ] Register/clobber convention tests where feasible.

## Migration Checklist

### Phase 0: Baseline Safety

- [x] Record current build commands:
      `make build`, `make disk`, `make test64`, `make test128-fast`,
      `make test128-fast-smoke`, `make testplus4`, `make testplus4-runtime`,
      `make diskplus4`.
- [x] Record that `make testplus4` is not yet a runtime gate.
- [x] Record resolved Plus/4 failure: `Disk code $00 phase $83`.
- [ ] Ensure no HAL migration starts before C64/C128 baseline gates are named.
- [ ] Preserve current C64/C128 behavior unless a test proves an existing bug.

### Phase 1: Plus/4 Runtime Harness

- [x] Add `xplus4` monitor connector modeled after the C128 VICE harness.
- [x] Add pass/fail symbol support from `.vs` files.
- [x] Detect timeout, hang, BRK, and CPU JAM.
- [ ] Detect reset explicitly.
- [ ] Add boot/title smoke.
- [x] Add minimal PRG runtime smoke proving xplus4 monitor harness plumbing.
- [ ] Add new-game-to-town smoke.
- [ ] Add dungeon-entry smoke.
- [ ] Add overlay-load smoke.
- [x] Add disk-setup smoke with valid save disk.
- [x] Add missing save media smoke.
- [x] Add wrong save media smoke.
- [x] Add product Disk Setup smoke for the marker create/readback path.
- [ ] Restore or replace the direct marker-init smoke. The product Disk Setup
      smoke currently covers the real path; the direct `$F000` call harness is
      too sensitive to bank/IRQ setup to keep as a default gate.
- [x] Add save-write smoke using the product `save_game` routine after title
      initialization, then inspect the host save disk for `P4.THE.GAME`.
- [x] Add save-load record smoke. First slice: seed `P4.THE.GAME` with a
      generated Plus/4-format save and prove `load_game` accepts it.
- [x] Add load-resume smoke using the product `load_game` plus
      `load_resume_game`, with the boot disk still mounted for tier restore.
- [x] Add command-channel status/error smoke for Plus/4 missing save media.
- [ ] Change `make testplus4` to run real runtime smoke after the harness is
      reliable.

Gate to leave Phase 1:

- [ ] `make testplus4-runtime` covers boot/title plus at least one disk setup
      success and one disk setup failure.
- [x] A valid-save-disk fixture can be created deterministically by the test
      harness for marker initialization.
- [x] A scripted Plus/4 product Disk Setup smoke boots from a D64, initializes
      a drive-9 save disk, reaches the real initialized-commit path, and checks
      the resulting `MORIA4.ID` marker on the host disk image.
- [x] A scripted Plus/4 product Disk Setup smoke with no drive-9 disk attached
      reaches the real initialization-failure path instead of hanging,
      resetting, or falsely committing setup. It now asserts DOS code `74`,
      disk status `74`, and diagnostic phase `$83`.
- [x] Plus/4 resident size pressure is cleared for the next runtime gate work:
      the product build now ends at `$C50E`, below `MAP_BASE=$C800`, after
      removing accidental C64 REU linkage from the Plus/4 resident image.
- [ ] Direct Plus/4 marker-initialization smoke must explicitly install RAM IRQ
      vectors and enter all-RAM mode before calling the banked
      `disk_marker_init` routine. Product Disk Setup is the active marker gate
      until that direct harness is reliable again.
- [x] Plus/4 save-write smoke reaches the real success carry path and creates
      `P4.THE.GAME` as a SEQ file on drive 9.
- [x] Plus/4 load-resume smoke reads a generated Plus/4 save file from drive 9,
      reaches `load_resume_game`, and resumes to `main_loop` without timeout,
      reset, BRK, or CPU JAM.
- [x] Save/load gate scaffolding is enabled in the default Plus/4 runtime
      suite. The generated fixture includes the Plus/4 marker file and uses the
      currently observed Plus/4 product load payload length.
- [x] A scripted Plus/4 product load smoke with a wrong `MORIA4.ID` marker
      reaches the load media-failure path instead of entering gameplay.
- [ ] Runtime tests can distinguish timeout, reset, BRK, CPU JAM, and friendly
      disk error return.

### Phase 2: HAL Contract Skeleton

- [x] Add `commodore/hal/` contract files.
- [ ] Add fail-loud missing-service stubs.
- [ ] Add platform capability/layout manifests.
- [ ] Document register, clobber, carry, IRQ, and ROM/RAM contracts for each
      service.
- [x] Wire C64 with thin adapters first.
- [x] Wire C128 with thin adapters second.
- [ ] Wire Plus/4 independently; do not use `c64_*` aliases for storage,
      banking, input, sound, or TED display services.

Phase 2 next task:

- [x] Write `commodore/hal/hal_storage.s` as the authoritative storage ABI:
      status codes, phase bands, required labels, register conventions,
      clobbers, residency/banking rules, and command-channel expectations.
- [x] Add platform storage adapter files under `commodore/{c64,c128,plus4}/hal/`
      without changing existing behavior yet.
- [x] Add a completeness/static check that fails if any platform does not
      provide each required storage label.

Storage adapter note:

- [x] The first storage adapter pass uses zero-byte `.label` aliases to avoid
      changing C64/C128/Plus4 memory layout or behavior. This is intentional:
      C64 default memory is already close enough to `$C000` that resident
      adapter code caused a layout assertion failure during implementation.
- [x] Plus/4 storage adapters point at `plus4_kernal_*` wrapper names for the
      low-level ROM/RAM + KERNAL boundary. Transitional `c64_disk_*` aliases
      remain inside Plus/4 only until old call sites migrate.
- [ ] Replace aliases with real platform-owned routines only one slice at a
      time, with C64/C128/Plus4 runtime gates named before each migration.

### Phase 3: Non-Storage HAL Migration

- [ ] Migrate platform capabilities/layout.
- [ ] Migrate lifecycle/runtime resync.
- [ ] Migrate screen clear/text/color.
- [ ] Migrate input/key repeat/text input.
- [ ] Migrate sound/SFX.
- [ ] Migrate overlay/asset loading.
- [ ] Migrate entropy/timers.
- [ ] After each migrated slice, remove the corresponding common-code hardware
      access and add a static audit rule.

### Phase 4: Storage HAL Migration

- [x] Define first-pass normalized storage error ABI.
- [ ] Confirm normalized storage error ABI against C64, C128, and Plus/4
      runtime behavior.
- [ ] Move filenames into platform storage implementations.
- [ ] Move logical file numbers and secondary addresses into platform storage.
- [ ] Move command channel reads into platform storage.
- [ ] Move drive probing and drive-specific behavior into platform storage.
- [ ] Keep C64, C128, and Plus/4 storage implementations independently owned.
- [ ] Make common save/load branch only on normalized storage errors.
- [ ] Preserve raw platform diagnostics in debug/status bytes.
- [ ] Require runtime proof for setup/save/load on C64, C128, and Plus/4 before
      accepting the storage HAL migration.

### Phase 5: Common-Code Purity Ratchet

- [x] Add forbidden-symbol audit.
- [x] Record current violations as a shrinking migration allowlist.
- [ ] Remove hardware literals from `commodore/common/`.
- [ ] Remove raw KERNAL calls from common storage paths.
- [ ] Reduce platform `#if C64/C128/PLUS4` branches in common game logic.
- [ ] Keep temporary exceptions only in `commodore/common/compat/` or explicitly
      named transition files.
- [ ] Delete compatibility aliases that make one platform look like another
      platform, especially C64-style banking aliases for Plus/4.

## Gate Checklist

### Every HAL Change

- [ ] `make build`
- [ ] `make test64`
- [ ] `make test128-fast`
- [ ] `make test128-fast-smoke`
- [ ] `make testplus4` once it is a real runtime smoke gate.
- [x] HAL boundary/static audit.
- [ ] `git diff --check`

### Broad Memory/Banking/Overlay/Storage Changes

- [ ] `make test128`
- [ ] Full C64 runtime suite.
- [x] Plus/4 boot/setup/save/load runtime smoke.
- [ ] Disk image manifest check for C64.
- [ ] Disk image manifest check for C128.
- [ ] Disk image manifest check for Plus/4.

### Disk Setup/Save/Load Changes

- [x] Plus/4 clean boot manually verified during save/load testing.
- [x] Plus/4 valid save disk setup manually verified.
- [x] Plus/4 wrong/missing save media behavior manually verified.
- [x] Plus/4 save disk initialization manually verified.
- [x] Plus/4 save write manually verified.
- [x] Plus/4 load resume manually verified.
- [ ] Friendly disk error reporting across all platforms.
- [x] No hang in the manually verified Plus/4 happy path.
- [x] No reset in the manually verified Plus/4 happy path.
- [x] No BRK escape in the manually verified Plus/4 happy path.
- [x] No CPU JAM in the manually verified Plus/4 happy path.
- [ ] Automated C64/C128/Plus4 disk setup/save/load gates.
      Plus/4 now has product setup, missing-media with command-channel
      diagnostics, wrong-media, save-write, and load-resume runtime gates;
      C64/C128 parity gates remain open.

## Normalized Storage Error ABI

Common code should branch on these semantic values. Platform-specific raw
status bytes should remain available for diagnostics.

```text
0   OK
1   Not found
2   No device
3   Write protected
4   Disk full
5   Wrong media
6   Device not ready
7   Unsupported device/protocol
255 Unknown
```

## Static Audit Rules

Fail the build if unapproved `commodore/common/` code contains:

- [ ] `$01`
- [ ] `$dd00`
- [ ] `$d000-$dfff` hardware access
- [ ] `$ff3e` / `$ff3f`
- [ ] Raw `KERNAL_*` disk calls
- [ ] `VIC`
- [ ] `CIA`
- [ ] `SID`
- [ ] `TED`
- [ ] `VDC`
- [ ] `1541`
- [ ] `1551`
- [ ] `BANK_*` processor-port constants
- [ ] New platform `#if C64`, `#if C128`, or `#if PLUS4` branches outside
      approved transition files.

## Session Handoff Notes

- [ ] Read this document before touching Plus/4 storage, banking, input, sound,
      or display.
- [ ] Read `docs/CROSS_PLATFORM_STRATEGY.md` before planning any platform beyond
      C64/C128/Plus4.
- [ ] Treat Plus/4 as a separate platform, not a C64 derivative.
- [ ] Treat C64/C128 as protected behavior baselines during HAL migration.
- [ ] Do not accept manual Plus/4 disk testing as a release gate once the
      harness exists.
- [ ] Update this checklist as phases are completed or gates change.
