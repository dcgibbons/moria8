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
      runtime gates. `make testplus4-runtime` now covers boot/title reachability,
      marker initialization directly, a scripted product Disk Setup success path
      against a freshly formatted drive-9 save disk, the missing drive-9
      save-media failure path, product save-write, and product load-resume from
      a generated Plus/4 save fixture.
- [x] `make testplus4` runs the Plus/4 runtime smoke gate. The old build-only
      target is preserved as `make testplus4-build`.
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

## C64/C128 Storage Baseline Gates

These are the protected storage baselines before Phase 4 moves more common
save/load behavior behind platform storage adapters.

C64 baseline:

- [x] `make test64` runs `save` (`commodore/c64/tests/test_save.s`) for save
      record layout, checksums, and floor-item persistence.
- [x] `make test64` runs `disk_swap`
      (`commodore/c64/tests/test_disk_swap.s`) for save-media prompt policy,
      marker handling, and one-drive/two-drive disk setup state.
- [x] `make test64` runs `main_loop`
      (`commodore/c64/tests/test_main_loop.s`) for title/game save-load
      dispatch behavior and disk setup failure/success branches.
- [x] `make test64` runs `score` (`commodore/c64/tests/test_score.s`) for the
      score-storage path.
- [x] `make test64` runs `disk_setup_product_smoke`, proving the product title
      Disk Setup path initializes an empty save disk on drive 9 and leaves
      `MORIA8.ID` visible as a SEQ file in the host save disk image.
- [x] `make test64` runs `save_write_product_smoke`, proving the product load
      path can resume from a generated save, run the product save command, and
      leave `THE.GAME` visible as a SEQ file in the host save disk image.
- [x] `make test64` runs `load_resume_product_smoke`, proving a generated C64
      save can enter `load_resume_game`, redraw the resumed state, print the
      welcome-back message, and reach the playable `main_loop` boundary before
      any follow-up save command.

C128 baseline:

- [x] `make test128-fast` runs `disk_swap128`
      (`commodore/c128/tests/test_disk_swap128.s`) for C128 disk setup and
      save-media prompt policy.
- [x] `disk_swap128` directly covers the C128 Disk Setup coordinator paths
      that confirm drive 9, handle a missing marker, initialize the marker,
      and commit the selected save drive without relying on product monitor
      choreography.
- [x] `make test128-fast` runs `main_loop128`
      (`commodore/c128/tests/test_main_loop128.s`) for C128 title/game
      save-load dispatch behavior and disk setup failure/success branches.
- [x] `make test128-fast-smoke` includes
      `boot_title_load_missing_savefile_smoke`, proving the title load path
      reports a missing save file instead of entering gameplay.
- [x] `make test128-fast-smoke` includes
      `boot_title_load_mounted_save_smoke`, proving mounted save media reaches
      the load/resume path from the title menu.
- [x] `make test128-fast-smoke` includes `boot_title_load_resume_smoke`,
      proving a generated C128 save can reach `load_resume_game`.
- [x] `make test128-fast-smoke` includes `boot_title_save_write_product_smoke`,
      proving the product save path can create/update `THE.GAME` on a mounted
      save disk and leave a SEQ save file visible in the host disk image.
- [x] `make test128-fast-smoke` includes `marker_init_d64_smoke`, a minimal
      real-D64 storage smoke that runs the C128 marker-init path against a
      freshly formatted drive-9 save disk and verifies the persistent
      `MORIA8.ID` contents are exactly `M8SAVE`.
- [ ] C128 still needs a product-level Disk Setup success smoke equivalent to
      the C64 and Plus/4 gates if we want UI-level coverage of that exact
      path. The lower-level real-D64 marker-init smoke is the current storage
      setup proof; do not treat monitor stops alone as semantic proof.

Plus/4 baseline:

- [x] `make testplus4-runtime` runs `disk_setup_product_plus4` for real product
      save-disk marker creation/readback.
- [x] `make testplus4-runtime` runs `disk_setup_missing_save_plus4` for missing
      drive-9 media and asserts DOS code `74`, disk status `74`, and diagnostic
      phase `$83`.
- [x] `make testplus4-runtime` runs `load_wrong_media_product_plus4` for wrong
      `MORIA4.ID` marker handling.
- [x] `make testplus4-runtime` runs `save_write_product_plus4`, proving the
      product save path creates `P4.THE.GAME` as a SEQ file on drive 9.
- [x] `make testplus4-runtime` runs `load_resume_product_plus4`, proving a
      generated Plus/4 save resumes gameplay without timeout, reset, BRK, or
      CPU JAM.

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
│   ├── hal_layout.s
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
- [x] Make `make testplus4` a runtime gate and preserve `make testplus4-build`
      for build-only artifact assembly.
- [x] Record resolved Plus/4 failure: `Disk code $00 phase $83`.
- [x] Ensure no HAL migration starts before C64/C128 baseline gates are named.
- [ ] Preserve current C64/C128 behavior unless a test proves an existing bug.

### Phase 1: Plus/4 Runtime Harness

- [x] Add `xplus4` monitor connector modeled after the C128 VICE harness.
- [x] Add pass/fail symbol support from `.vs` files.
- [x] Detect timeout, hang, BRK, and CPU JAM.
- [x] Detect monitor connection reset/closure explicitly. Product smokes now
      report reset/closed monitor transport as structured failures instead of
      Python tracebacks; `test_vice_connector.py` covers the connector behavior.
- [x] Add boot/title smoke.
- [x] Add minimal PRG runtime smoke proving xplus4 monitor harness plumbing.
- [x] Add new-game-to-town smoke.
- [x] Add dungeon-entry smoke.
- [x] Add overlay-load smoke.
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
- [x] Change `make testplus4` to run real runtime smoke after the harness is
      reliable.

Gate to leave Phase 1:

- [x] `make testplus4-runtime` covers boot/title plus at least one disk setup
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
- [x] Plus/4 new-game-to-town smoke boots the product disk, enters the real
      title `N)ew` flow through deterministic scripted input, completes character
      creation, loads the town/start overlays, and reaches the first gameplay
      loop.
- [x] Plus/4 dungeon-entry smoke continues from the product new-game flow,
      moves onto the town down-stairs, issues `>`, and reaches
      `dungeon_generate`.
- [x] Plus/4 overlay-load smoke boots the product disk and loads every product
      overlay ID from disk, `OVL_STARTUP` through `OVL_SPELL`, failing on the
      first `overlay_load` carry error.
- [x] Plus/4 load-resume smoke reads a generated Plus/4 save file from drive 9,
      reaches `load_resume_game`, and resumes to `main_loop` without timeout,
      reset, BRK, or CPU JAM.
- [x] Save/load gate scaffolding is enabled in the default Plus/4 runtime
      suite. The generated fixture includes the Plus/4 marker file and uses the
      currently observed Plus/4 product load payload length.
- [x] A scripted Plus/4 product load smoke with a wrong `MORIA4.ID` marker
      reaches the load media-failure path instead of entering gameplay.
- [x] Runtime tests can distinguish timeout, monitor reset/close, BRK, CPU JAM,
      and friendly disk error return.

### Phase 2: HAL Contract Skeleton

- [x] Add `commodore/hal/` contract files.
- [x] Add fail-loud missing-service stubs.
- [x] Add platform capability/layout manifests.
- [x] Document register, clobber, carry, IRQ, and ROM/RAM contracts for each
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
- [x] Add opt-in common fail-loud stubs in
      `commodore/common/hal_missing_service_stubs.s` for non-storage contracts.
      Product builds do not import these stubs; `check_hal_missing_stubs.py`
      gates stub coverage against the contract files.
- [x] Add machine-readable capability/layout manifests at
      `commodore/{c64,c128,plus4}/hal/manifest.json`. The static
      `check_hal_manifests.py` gate verifies required platform facts, including
      display class, banking mechanism, default device numbers, compatible
      drive assumptions, and capability flags.
- [x] Add enforceable contract documentation for lifecycle, memory, IRQ,
      screen, input, sound, and asset-loader services. The
      `check_hal_contract_docs.py` gate verifies every non-storage required
      export has an explicit contract entry; storage remains covered by the
      dedicated ABI text and storage export checker.
- [x] First Plus/4 independence slice after storage closeout: the Plus/4
      all-RAM IRQ vector installer now uses Plus/4-owned labels instead of
      `c64_*` compatibility names. The Plus/4 runtime harness calls the
      renamed symbol, and `check_plus4_hal_independence.py` prevents those IRQ
      compatibility labels from returning.
- [x] Second Plus/4 independence slice: the non-C128 hidden-RAM tier-name pool
      contract is now `PLATFORM_TIER_NAME_POOL_*`. C64 keeps legacy
      `C64_TIER_NAME_POOL_*` constants only for C64 tests; Plus/4 no longer
      defines the C64-shaped pool names, and the Plus/4 independence checker
      prevents them from returning.
- [x] Third Plus/4 independence slice: common inventory overlay restore now
      calls `hal_irq_install_runtime` instead of the C64 IRQ-vector installer
      name. C64 and Plus/4 export their platform-owned installers through that
      HAL label, and the Plus/4 independence checker prevents the common path
      from regressing to `c64_install_ram_irq_vectors`.
- [x] Fourth Plus/4 independence slice: the shared non-C128 overlay-runtime
      product flag is now `PLATFORM_PRODUCT_OVERLAY_RUNTIME`. Plus/4 no longer
      defines `C64_PRODUCT_OVERLAY_RUNTIME`, and common overlay-runtime
      conditionals no longer require a C64-shaped product define.
- [x] Fifth Plus/4 independence slice: the shared non-C128 IRQ-vector runtime
      product flag is now `PLATFORM_PRODUCT_IRQ_VECTOR_RUNTIME`. C64 keeps the
      legacy `C64_PRODUCT_IRQ_VECTOR_RUNTIME` name for C64-owned input code,
      but common inventory overlay restore no longer depends on a C64-shaped
      product define.
- [x] Sixth Plus/4 independence slice: Plus/4 lifecycle/runtime-service install
      and resync labels are Plus/4-owned (`plus4_platform_*`) instead of
      reusing C64-shaped `platform_*_c64` names. The installed shared service
      vectors and runtime behavior are unchanged.
- [x] Seventh Plus/4 independence slice: the shared 40-column wizard menu
      helper is named `wizard_40col_menu_display` instead of
      `wizard_c64_menu_display`; C64 and Plus/4 both call the neutral helper.
- [x] First lifecycle/runtime-resync cleanup: common overlay-return paths now
      call `platform_runtime_resync_api` instead of naming C128 runtime guard
      helpers directly. C128 keeps `c128_restore_runtime_guards` as a
      platform-owned implementation detail.
- [x] Second lifecycle/runtime-resync cleanup: the C128-only generation overlay
      restore helper in common code now has a platform-neutral name,
      `platform_restore_generation_overlay`, instead of a C128-shaped helper
      name.
- [x] First capabilities/layout cleanup: the shared 40-column dungeon map
      dimensions are named `MAP40_*` instead of `C64_MAP_*`, so Plus/4 no
      longer inherits C64-shaped map-size constants.
- [x] Platform manifests now record and statically verify visible rows and
      viewport geometry against each platform's screen implementation before
      screen code moves behind HAL calls.
- [x] Added assembler-visible layout HAL constants for screen dimensions,
      viewport, message, status, and input rows. The new
      `check_hal_layout_exports.py` gate verifies those constants against the
      existing platform screen implementations without changing runtime code.
- [x] Each platform screen backend now imports its layout HAL constants and
      asserts that legacy `SCREEN_*`, `VIEWPORT_*`, and row constants match
      the HAL contract. Runtime code is unchanged.
- [x] Legacy `SCREEN_*`, `VIEWPORT_*`, and row constants are now aliases to
      the layout HAL constants in each platform screen backend. Existing
      common callers keep their names while the source of truth moves to HAL.
- [x] Layout HAL now includes platform map dimensions. The static layout
      checker verifies them against the current `dungeon_data.s` map constants
      without making `dungeon_data.s` depend on screen/layout import order.
- [x] Layout is now part of the top-level HAL contract aggregator. The
      contract-doc checker recognizes constant-only contracts, so layout stays
      documented as platform constants instead of being forced into a fake
      service ABI.

Storage adapter note:

- [x] The first storage adapter pass uses zero-byte `.label` aliases to avoid
      changing C64/C128/Plus4 memory layout or behavior. This is intentional:
      C64 default memory is already close enough to `$C000` that resident
      adapter code caused a layout assertion failure during implementation.
- [x] Plus/4 storage adapters point at `plus4_kernal_*` wrapper names for the
      low-level ROM/RAM + KERNAL boundary. Transitional `c64_disk_*` storage
      aliases have been removed from the Plus/4 port; common title loading,
      Disk Setup marker writes, and marker validation now call storage HAL
      labels instead of C64-named helpers.
- [x] First non-alias slice: save-record filename policy is platform-owned via
      `hal_storage_save_{probe,read,write}_name` labels. Common save/load code
      no longer owns `THE.GAME`/`P4.THE.GAME` filename bytes.
- [x] Second filename slice: save-disk marker filename/magic policy is
      platform-owned via `hal_storage_marker_*` labels. Common disk setup and
      marker validation no longer own `MORIA8.ID`/`MORIA4.ID` filename bytes or
      marker magic bytes.
- [x] First numeric policy slice: storage logical file numbers, secondary
      addresses, command channel number, marker file number, and program load
      file number are platform-owned constants exported by each storage HAL.
- [x] First command-status slice: command-channel status reads are exported as
      `hal_storage_read_command_status`; C128 Disk Setup no longer owns the
      command-channel read routine in common code.
- [x] Second command-status slice: command-channel status classification is
      exported as `hal_storage_command_status`. C128 and Plus/4 consumers now
      classify the latest captured command-channel DOS digits through the
      storage HAL instead of reading platform diagnostic bytes directly; C64
      exports the contract without growing the byte-tight product image.
- [x] First raw-diagnostics slice: platform storage implementations export
      read-only `hal_storage_diag_{code,phase,readst,device,dos0,dos1}` byte
      labels. C128 maps these to `disk_diag_*`; Plus/4 maps them to
      `disk_error_*`; C64 maps the currently available compact fields without
      growing resident code. This is an ABI surface only; it does not change
      player-facing error text yet.
- [x] First normalized save-media status slice: `hal_storage_save_media_status`
      is the required adapter entry point for classifying the most recent
      save-media validation failure. The older boolean
      `hal_storage_save_media_error_is_io` transition surface has been removed.
- [x] Third filename slice: title-art filename policy is platform-owned via
      `hal_storage_title_name`. Common title loading and C128 title-cache
      loading no longer own `T64`/`T128` filename bytes.
- [x] Fourth filename slice: overlay asset filename policy is platform-owned
      via `hal_storage_overlay_name_{lo,hi,len}`. Common overlay loading and
      REU preload display no longer own `64.*`/`4.*`/`128.*` overlay filename
      bytes. C128 keeps the bytes in the overlay-state area through
      `hal/storage_overlay_names.s` so the byte-tight Disk I/O resident payload
      does not grow. Isolated C64 unit assemblies that intentionally omit the
      storage HAL use `common/hal_storage_overlay_test_stub.s`; product builds
      are guarded out of that shim and must export the real platform labels.
      Overlay filename labels are length-based for KERNAL calls, but each
      filename must also carry a trailing zero for REU preload display.
      `tools/check_hal_storage_exports.py` now gates that terminator contract.
- [x] Fifth filename slice: tier data filename policy is platform-owned via
      `hal_storage_tier_name_{lo,hi,len}` and per-tier
      `hal_storage_tier_{1,2,3,4}_name` labels. Common tier loading, C64 REU
      preload display, and C128 cache preload no longer own
      `MONSTER.DB.1` through `MONSTER.DB.4` filename bytes. C128 keeps the
      tier filename bytes in the resident-world payload through
      `hal/storage_tier_names.s`; putting those bytes in the Bank 0 startup
      image would cross the resident-world boundary. Isolated C64 unit
      assemblies use `common/hal_storage_tier_test_stub.s`. Tier filename
      lengths are KERNAL length labels, and each tier filename must also carry
      a trailing zero for preload display; `tools/check_hal_storage_exports.py`
      gates that contract.
- [x] Sixth filename slice: high-score filename policy is platform-owned via
      `hal_storage_score_{read,write,scratch}_name` labels. Common high-score
      I/O no longer owns `HALL.OF.FAME`/`P4.HALL.FAME` filename bytes or the
      Plus/4-specific filename branch. The HAL boundary allowlist dropped the
      stale `score_io.s` `#if PLUS4` entry, and
      `tools/check_hal_storage_exports.py` now requires the score filename
      labels for all three platforms.
- [x] High-score sequential I/O call binding now goes through storage HAL
      labels. `score_io.s` no longer has raw `KERNAL_*` calls; the remaining
      platform-specific KERNAL/banking behavior lives behind each platform's
      `hal_storage_*` exports and existing caller-owned KERNAL visibility
      setup.
- [x] Replace remaining Plus/4 storage aliases with platform-owned routines.
      C64 keeps C64-named routines inside its own implementation and C64 unit
      fixtures; Plus/4 no longer exports C64-shaped storage compatibility
      labels.
- [ ] Replace remaining aliases with real platform-owned routines only one slice at a
      time, with C64/C128/Plus4 runtime gates named before each migration.

### Phase 3: Non-Storage HAL Migration

- [ ] Migrate platform capabilities/layout.
- [ ] Migrate lifecycle/runtime resync.
- [ ] Migrate screen clear/text/color.
- [ ] Migrate input/key repeat/text input.
- [ ] Migrate sound/SFX.
- [ ] Migrate overlay/asset loading.
      Backlog: C64 `S)TART` should match C128 by preserving valid REU overlay
      cache contents across start-over. Restart should reset session/game state
      without reloading all overlays from program media unless the REU cache is
      missing or invalid.
- [ ] Migrate entropy/timers.
- [ ] After each migrated slice, remove the corresponding common-code hardware
      access and add a static audit rule.

### Phase 4: Storage HAL Migration

- [x] Define first-pass normalized storage error ABI.
- [x] Confirm normalized save-media wrong-media-vs-I/O classification against
      C64, C128, and Plus/4 runtime behavior.
      Common save/load now branches on `HAL_STORAGE_STATUS_WRONG_MEDIA` from
      `hal_storage_save_media_status`; all other normalized statuses take the
      disk-error path.
      C128 unit coverage now requires positive DOS `62` evidence before a
      failed marker read is classified as wrong save media; ambiguous/no-disk
      marker failures classify as disk I/O errors.
      C64 and C128 currently report readable wrong media as
      `HAL_STORAGE_STATUS_WRONG_MEDIA` and other save-media failures as
      `HAL_STORAGE_STATUS_UNKNOWN`; richer device-status normalization
      remains future work because the resident image is byte-tight.
- [x] Move filenames into platform storage implementations.
      Save-record filenames are done; save-disk marker filenames, title/overlay
      marker filenames are done; title-art asset filenames are done; overlay
      asset filenames are done; tier data filenames are done; score filenames
      are done.
- [x] Move logical file numbers and secondary addresses into platform storage.
- [x] Move command channel reads into platform storage.
- [x] Move save/load sequential I/O call binding to storage HAL adapter labels.
      This removed the raw `KERNAL_*` save/load bindings from
      `commodore/common/save.s`; `docs/hal_boundary_allowlist.txt` now tracks
      the smaller baseline.
      C64 save/load now explicitly banks in `BANK_NO_BASIC` before sequential
      stream I/O because its current adapter still exposes raw `CHKIN`, `CHRIN`,
      `CHROUT`, and `READST` vectors for resident-size reasons.
      C64 adapter wrappers must bank KERNAL in before restoring A/X/Y and
      calling the target routine; otherwise argument-sensitive calls such as
      `SETNAM` and `SETLFS` receive the bank-control value instead of the
      caller's arguments. The C64 product save/load smokes now force drive 9
      online with `-drive9type 1541` so the two-drive path is actually tested.
- [x] Move high-score sequential I/O call binding to storage HAL adapter labels.
      `score_io.s` now uses local `SCORE_*` aliases to the platform
      `hal_storage_*` routines and no longer needs raw KERNAL entries in the
      common HAL boundary allowlist.
- [x] Move C128 Disk Setup marker-init sequential I/O call binding to storage
      HAL adapter labels. `disk_setup_banked.s` now uses local `FEAT_*`
      aliases for `SETNAM`, `SETLFS`, `OPEN`, `CLOSE`, `CLRCHN`, `READST`,
      `CHKOUT`, and `CHROUT`; the C128 path still owns its explicit
      KERNAL-visible entry/exit around those calls.
- [x] Move Disk Setup save-marker validation sequential I/O call binding to
      storage HAL adapter labels. `disk_swap.s` now uses local `SWAP_*`
      aliases for marker `SETNAM`, `SETLFS`, `OPEN`, `CLOSE`, `CLRCHN`,
      `READST`, `CHKIN`, and `CHRIN`; remaining `disk_swap.s` boundary entries
      are target-conditionals and C64 bank visibility, not raw KERNAL symbol
      use.
- [x] Move C128 title-cache filename setup call binding to storage HAL adapter
      labels. `title_cache_runtime128.s` now uses `hal_storage_setnam` and
      `hal_storage_setlfs`; the remaining C128-specific title-cache boundary
      is its Bank 1 cache/runtime behavior, not raw storage KERNAL symbols.
- [x] Move drive probing and selected-drive init into platform storage.
      Common Disk Setup now calls `hal_storage_probe_media`, and the one-drive
      prompt path calls `hal_storage_init_selected_drive`; C64, C128, and
      Plus/4 own the KERNAL/ROM-visible command-channel implementation.
      C128 keeps the drive-probe/init helper in resident-world space through
      `hal/storage_drive.s` so the byte-tight resident disk-I/O payload does
      not grow past `$AEFF`.
- [x] Keep C64, C128, and Plus/4 storage implementations independently owned.
      The last Plus/4 `c64_disk_*` compatibility labels were removed. Shared
      title loading, marker validation, and non-C128 Disk Setup now bind
      through `hal_storage_*`; remaining `c64_disk_*` names are confined to
      the C64 implementation, its adapter aliases, and C64 test fixtures.
      Manual smoke on C64, C128, and Plus/4 passed after this slice.
- [x] Make common save/load branch only on normalized save-media errors.
      C64 unit coverage now checks `save_game` error-message selection and the
      normalized classifier directly; C128 unit coverage checks ambiguous,
      wrong-media, and command-channel-backed marker failures; Plus/4 runtime
      gates cover setup, wrong-media, save-write, and load-resume behavior.
- [x] Add the first shared DOS-status normalization primitive.
      `storage_status_from_dos_digits` maps command-channel status digits for
      `00`, `26`, `62`, `72`, and `74` into `HAL_STORAGE_STATUS_*` values.
      C64 unit coverage exercises the mapping table directly; C128 setup
      status capture and C128/Plus/4 save-media classification now use the
      shared semantic helper where they already have command-channel status
      digits. The helper is opt-in via `STORAGE_STATUS_HELPER` and is not
      linked into the byte-tight C64 product image.
- [x] Add C128 unit coverage for setup-status capture.
      `disk_swap128` now verifies that Disk Setup's C128 init-failure status
      capture preserves write-protect, disk-full, and drive-not-ready codes
      through the shared DOS-status normalizer while leaving unknown statuses
      alone.
- [x] Add a setup-status classification adapter.
      `hal_storage_setup_status` now exposes the most recent Disk Setup
      initialization failure as `HAL_STORAGE_STATUS_*`, and the Disk Setup
      failure overlay uses that semantic status for write-protect, disk-full,
      and drive-not-ready messages while preserving raw diagnostic bytes for
      debug/status detail.
- [x] Add save/load stream status classification adapters.
      `hal_storage_save_stream_status` and `hal_storage_load_stream_status`
      expose the current save/load record stream result as `HAL_STORAGE_STATUS_*`
      without changing the underlying sequential I/O path. C64 unit coverage
      verifies OK, not-found, unsupported, and generic I/O classifications.
- [x] Consume save/load stream classifications for message selection.
      C128 and Plus/4 save/load stream failure exits now select existing
      user-facing messages from semantic `HAL_STORAGE_STATUS_*` values. C64
      keeps the product path byte-neutral while unit tests cover the shared
      status-to-message selectors.
- [x] Add command-channel status classification adapter.
      `hal_storage_command_status` exposes the most recently captured command
      channel DOS digits as `HAL_STORAGE_STATUS_*`. C128 Disk Setup capture,
      C128 setup-status classification, and C128/Plus/4 save-media
      classification now call this adapter instead of decoding raw diagnostic
      bytes in common control flow. `disk_swap128` directly covers the adapter
      mappings for `00`, `26`, `62`, `72`, `74`, and an unmapped status.
- [x] Preserve raw platform diagnostics behind storage HAL labels.
      `hal_storage_diag_code`, `hal_storage_diag_phase`,
      `hal_storage_diag_readst`, `hal_storage_diag_device`,
      `hal_storage_diag_dos0`, and `hal_storage_diag_dos1` are now required
      storage exports. C128 unit coverage verifies the labels expose the native
      diagnostic bytes; C64 has a static no-growth contract for the compact
      aliases; Plus/4 exports its existing diagnostic byte set.
- [x] First richer save/load diagnostics slice.
      C128 and Plus/4 save/load message selection now maps semantic
      write-protect, disk-full, and drive-not-ready storage statuses to
      friendly direct messages instead of always falling back to `Disk error!`.
      C64 remains product byte-neutral and continues to use the existing
      compressed generic save/load messages.
- [x] Tighten C128 save-media ownership after drive re-init failures.
      The C128 storage drive-init adapter now returns carry from the command
      channel status, and C128 media ownership is only updated to program/save
      media after a successful init. `disk_swap128` covers the failure case so
      a failed save-drive re-init clears `c128_media_state` instead of letting
      save continue into the overwrite probe.
- [ ] Continue richer save/load diagnostics beyond the first friendly-message
      mappings, especially raw diagnostic display for still-unknown failures.
- [x] Require runtime proof for setup/save/load on C64, C128, and Plus/4 before
      accepting the storage HAL migration.
      Current C128 runtime coverage protects title load missing/mounted save,
      product save-write, save-media failure display, and load-resume. The
      save-media failure smoke uses a deterministic test-only marker-read
      failure after the loaded game reaches the command loop; the lower-level
      `disk_swap128` unit owns the media-state assertion. C128 setup now has a
      real-D64 marker-init smoke that verifies the host disk image contains a
      valid `MORIA8.ID` marker after the C128 storage path runs.
- [x] Declare structural storage HAL migration complete.
      Save/load, high-score I/O, Disk Setup marker init/validation, selected
      drive probing/init, storage filename ownership, logical file numbers,
      secondary addresses, command-channel status reads, diagnostic exports,
      and C128 title-cache filename setup now bind through `hal_storage_*`
      instead of raw common-code storage KERNAL calls.
      Remaining storage-phase work is backlog quality/policy work: richer
      diagnostics for still-unknown failures and the `io_kernal_consts.s`
      ABI-constant exception tracked by the common-code purity ratchet.

### Phase 4A: Asset Loader HAL Boundary

This is explicitly not part of the structural storage HAL closeout. Storage HAL
owns record/file/session semantics for saves, scores, disk setup, markers, and
storage diagnostics. Asset Loader HAL should own runtime asset loading policy:
overlay PRGs, string banks, title-art bytes, cache restore/fallback behavior,
target-bank setup, and post-load channel cleanup.

- [x] Define the first asset-loader HAL entry point.
      `hal_asset_load` is now a required platform export for the platform's
      KERNAL LOAD equivalent. `hal_asset_load_prg_header` is the planned
      platform-owned PRG-header load transaction boundary: SETNAM, SETLFS,
      LOAD, CLOSE, CLRCHN, destination-bank setup, OS visibility, and post-load
      cleanup. The
      existing `AssetLoad()` macro routes through the raw-load HAL label on
      C64, C128, and Plus/4, and `tools/check_hal_asset_exports.py` verifies
      both asset-loader exports.
- [x] Extend asset-loader HAL entry points for platform-owned KERNAL LOAD
      setup, destination-bank setup, cleanup, and error/status reporting.
      First gate: `check_hal_asset_exports.py` now verifies that each platform
      exports the raw LOAD, PRG-header transaction, title-load transaction,
      and asset-channel cleanup labels, that `AssetLoad()` routes through
      `hal_asset_load`, and that the current PRG-header transaction body owns
      SETNAM, SETLFS, LOAD, CLOSE, CLRCHN, plus C128 destination-bank setup.
      Runtime asset errors still use carry status only; richer user-facing
      diagnostics remain a backlog item until a concrete failure requires it.
- [x] Move common `overlay.s` disk-load orchestration behind Asset Loader HAL.
      `overlay_load_disk` routes C64, C128, and Plus/4 through
      `hal_asset_load_prg_header`; the C128 overlay-cache preload path also
      calls that HAL label instead of the C128 implementation name directly.
      `check_hal_asset_exports.py` prevents raw KERNAL LOAD transactions,
      direct `AssetLoad()`, and direct `c128_preload_asset_load` calls from
      returning to `overlay_load_disk`. The targeted Plus/4
      `overlay_load_plus4` runtime smoke passed after this slice.
- [x] Move common `string_bank.s` KERNAL LOAD orchestration behind Asset Loader
      HAL.
      `bank_load_recall` now passes the recall-bank filename to
      `hal_asset_load_prg_header`; SETNAM, SETLFS, LOAD, CLOSE, CLRCHN, and
      serial-bus display-bank cleanup belong to the platform transaction.
      The C64 subsystem test stub now models that transaction cleanup, and
      `check_hal_asset_exports.py` prevents raw KERNAL LOAD orchestration from
      returning to `string_bank.s`.
- [x] Revisit title-art loading so C64/C128/Plus4 all use one explicit
      asset-loader contract while preserving C128 Bank 1 cache behavior.
      `hal_asset_load_title` is now required on every platform. C64 and
      Plus/4 own their MAP_BASE title-load transaction in platform config;
      C128 keeps the Bank 1 title cache wrapper and delegates disk load to the
      same HAL label. `check_hal_asset_exports.py` verifies the platform
      title transactions and prevents common title code from returning to raw
      storage/load choreography.
- [x] Move tier-data disk loading behind Asset Loader HAL.
      `tier_load_disk` now selects the platform-owned tier filename and calls
      `hal_asset_load_prg_header`; common tier code no longer performs
      SETNAM, SETLFS, LOAD, CLOSE, CLRCHN, KERNAL entry/exit, or serial-bus
      bank cleanup. `check_hal_asset_exports.py` now guards the tier disk-load
      path alongside overlay, string-bank, and title paths.
- [x] Move asset channel cleanup behind Asset Loader HAL.
      `hal_asset_close_channel` is now required on every platform. The common
      REU preload cleanup in `tier_init` calls that HAL service instead of raw
      CLOSE/CLRCHN vectors, and `check_hal_asset_exports.py` verifies the
      C64/Plus4 standalone close transactions plus the common call site. C128
      keeps close/CLRCHN inside `c128_preload_asset_load`; its exported cleanup
      label is a zero-byte no-op because the common caller is non-C128-only.
- [x] Keep `hal_storage_*` filename tables available as data inputs until a
      separate asset-name namespace is justified by real duplication or policy
      differences.
      No `hal_asset_*name*` namespace exists yet. `check_hal_asset_exports.py`
      now rejects premature asset-name labels and verifies overlay/tier common
      asset paths still consume the existing platform-owned `hal_storage_*`
      filename inputs.

### Phase 5: Common-Code Purity Ratchet

- [x] Add forbidden-symbol audit.
- [x] Record current violations as a shrinking migration allowlist.
- [ ] Remove hardware literals from `commodore/common/`.
      First slice: common RNG no longer owns CIA/TED timer register literals or
      a Plus/4 target branch. `hal_entropy_timer{0,1}_{lo,hi}` are now
      platform-owned HAL constants exported from each platform config, and
      `check_hal_entropy_exports.py` verifies both the exports and the common
      RNG call site.
- [x] Remove raw KERNAL calls from common storage paths.
      The remaining common `KERNAL_*` allowlist entries are
      `io_kernal_consts.s` ABI constants, not active storage behavior.
      Raw/common LOAD orchestration remains an Asset Loader HAL concern.
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
- [x] `make testplus4` once it is a real runtime smoke gate.
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
- [x] Automated C64/C128/Plus4 disk setup/save/load gates.
      Plus/4 now has product setup, missing-media with command-channel
      diagnostics, wrong-media, save-write, and load-resume runtime gates;
      C64 now has product setup, save-media-fail, load-resume, and save-write smokes;
      C128 now has real-D64 marker initialization, product title-load
      missing/mounted-save, save-media-fail, load-resume, and save-write
      smokes.

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
