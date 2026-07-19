# Apple IIe Port Plan

Implementation plan for porting moria8 to the Apple IIe under
`platforms/apple2/`. This is the process document; the memory placement
source of truth will be `docs/APPLE2_MEMORY_POLICY.md`, produced by
milestone M0.

## Status and Gating

**The port is gated on branch `work16` merging into `origin/main`.**
work16 changes dungeon generation and monster behavior across 18 core
files (+~3K net core lines) and modifies
`platforms/commodore/common/save.s` (+101 lines), which this port reuses
verbatim. Starting before the merge would bake stale module sizes into
the M0 closure table and force M3 bring-up to debug systems whose
semantics are moving. (Branch `work15` is already merged as PR #46 and
is byte-identical to main.)

Safe to do before the merge (core-independent M0 verifications):

- AUXMOVE ($C311) carry polarity, parameter behavior, INTC3ROM-vs-
  SLOTC3ROM selection ($C00B), and register clobbers
- MAME `apple2ee` Lua memory-peek spike (main and aux RAM)
- AppleCommander CLI flag verification and version pin
- ProDOS 8 redistribution terms check
- `tools/prg_to_bin.py`

After the merge: rebase the `apple2` branch, then run M0's measurement
against the merged tree.

## Locked Decisions

- Target: Apple IIe 128K, plain NMOS 6502 opcodes only (must also run on
  enhanced IIe/IIc).
- Display: 80-column text gameplay (C128 layout values).
- OS/storage: ProDOS 8 via MLI.
- Directory: `platforms/apple2/` as a peer platform.
- Kick Assembler retained; MAME `apple2ee` for the headless harness;
  AppleCommander (java jar, auto-download like KickAss) for `.po`
  images.
- Process: full parity, hardest-problem-first, modeled on the Plus/4
  port. No vertical slices, no scaffolding, no stubs-to-be-replaced, no
  feature-gating defines, no probe-only builds. Everything in the tree
  at every milestone is the shipping architecture.

## Ground Rules From Repo Verification

**The cx16 branch is a process reference only, never a code source.**
cx16 branched from `2993e57` and carries ~10,450 insertions across ~100
core files that do not exist on main. Its `main.s` imports core files
absent here. Bind against main's core exactly as c64/c128/plus4 do.

Reference files to study:

- `platforms/commodore/c64/main.s` — import cascade + overlay
  segmentdefs (the canonical "linker script")
- `platforms/commodore/c128/main.s` + `memory128.s` — split-payload
  model, play/persist broker, five-facts runtime-load contract
- `platforms/commodore/c128/hal/layout.s` — 80-column layout values
- `platforms/commodore/c64/hal/*` — manifest/policy templates
- `platforms/commodore/common/overlay.s` — `overlay_load` semantics
- `platforms/commodore/common/save.s` — storage primitive surface
- Branch `cx16`, process shape only:
  `platforms/cx16/{check_memory_contract.py, harness_smoke.py, Makefile,
  memory.s}`

Verified enablers (direct inspection, high confidence):

- All core map access goes through `MapRead_*`/`MapWrite_*` macros
  (25 files); only `core/dungeon_data.s` row tables use `MAP_BASE`
  arithmetically. The map can live in aux RAM behind platform accessors.
- `core/rng.s` reads entropy via four `lda absolute` of
  `hal_entropy_timer*` labels; pointing them at RAM counters needs zero
  core change.
- Core resolves these names via Kick `-libdir`, so the platform supplies
  same-named files with zero core edits: `mmu_macros.s`,
  `vic_palette_consts.s`, `creature_data/creature_tiers.s`,
  `compat/hal_storage_tier_test_stub.s`, and `../hal/hal_contract.s`
  (resolvable with `-libdir hal` from `platforms/apple2/`, where
  `hal/../hal/` self-resolves).
- Core references REU symbols in three files (`title_sysinfo_banked.s`,
  `game_loop.s`, `tier_manager.s`); apple2 ships a permanent
  inert-symbol `reu_stub.s` (same class as Plus/4's non-REU handling).
- 21 core files gate on `C128`/`PLUS4` consts; apple2 `main.s` declares
  `.const C128 = false`, `.const PLUS4 = false` and builds with
  `-define APPLE2`.
- No `.cpu` directives anywhere; Kick emits NMOS 6502 by default.
  `check_6502_lint.py` stays in the gate.
- Core raw-addresses these, so they must be main RAM: tier name pool
  (`tier_manager.s:474`, `monster.s:1531`), `BANKED_DATA` window
  (`tier_manager.s:471`), floor-item table, creature scratch.
- `core/item_actions_overlay.s:340` `cmp #40` is a false positive:
  item-ID dispatch (wands 39-42), not a column constant. No change.

## Memory Map

### Main RAM

| Range | Size | Owner |
| --- | ---: | --- |
| `$0000-$00FF` | 256 | ZP: core keeps `$02-$8F` unchanged; platform owns `$90-$EF` (state, 4 entropy counter bytes, ~24 B aux-read thunk); `$F0-$FF` reserved |
| `$0100-$01FF` | 256 | Stack |
| `$0200-$03CF` | 464 | Platform scratch: ZP save buffer (238 B), MLI parameter blocks, loader state |
| `$03D0-$03FF` | 48 | ProDOS/reset/IRQ vectors — reserved |
| `$0400-$07FF` | 1,024 | 80-col text page, main half (odd columns); screen holes (`$x78-$x7F`) never touched |
| `$0800-$09FF` | 512 | Floor-item table (256) + creature scratch (256) — core raw-addressed |
| `$0A00-$9DFF` | 37,888 | Resident payload region (multiple Kick segments, C128-style splits) |
| `$9E00-$A5FF` | 2,048 | Tier name pool (`PLATFORM_TIER_NAME_POOL_BASE`) — core raw-addressed |
| `$A600-$BAFF` | 5,376 | Shared overlay/tier window (`BANKED_DATA_BASE`); C64 mutually-exclusive semantics unchanged (`overlay_load` invalidates tier). Overlay code region `$A600-$B5FF` (4,096 >= C128 max slot 4,088; 8 B spare); BFS queue (1,024) at `$B600-$B9FF` (`$BA00-$BAFF` = 256 B slack in overlay mode, tier bytes in tier mode) — legal because OVL.GEN occupies the window exactly when BFS runs and tier data is already invalidated (identical to C64's `$E000` sharing) |
| `$BB00-$BEFF` | 1,024 | ProDOS MLI file I/O buffer (page-aligned, one open file) |
| `$BF00-$BFFF` | 256 | ProDOS global page (MLI entry `JSR $BF00`) |

The C64 RuntimeBanked class (`$F000`, 4,080 B) disappears as a class:
there is no ROM shadow on the Apple II, so its content is ordinary
resident bytes already inside the 51,481 B figure. Language Card RAM is
not used (ProDOS owns it; whether the `$D000` bank 2 area is partially
free is LOW confidence — a post-M4 growth area only, after verification
against the ProDOS 8 Technical Reference).

### Aux RAM (behind accessors only; ALTZP stays off)

| Range | Size | Owner |
| --- | ---: | --- |
| aux `$0400-$07FF` | 1K | Text page aux half (even columns) |
| aux `$0800-$3B0B` | 13,068 | Live map, 198x66 (mirrors C128 layout values) — all access via thunked MapRead/MapWrite |
| aux `$3B0C-$BFFF` | ~34K | Overlay cache (hot classes) + play/persist payload cache — exact manifest pinned in M0. Total swappable content (~40.9K by C128 numbers: 29,254 overlays + 8,424 play + 2,395 persist + 821 names) exceeds this space, so ~7K of cold classes remain disk-on-demand by design |

ProDOS 8 1.x on a 128K machine auto-creates the `/RAM` volume in aux
memory spanning roughly aux `$0800-$BFFF` — exactly the map+cache
region above. Policy: the game never issues I/O to `/RAM` (overwriting
aux is then safe; standard 128K practice), and boot may deallocate it.
The `/RAM` driver and quit dispatcher live in aux LC `$D000-$FFFF`,
which is why the LC stays out of scope above. ProDOS 8 1.x vs 2.x
`/RAM` creation behavior is an M0 verification item.

### Closure Arithmetic (the M0 equation)

Measured content (`docs/ARCHITECTURE.md`): C64 gameplay-concurrent =
51,481 B (image 47,401 + `64.bank` 4,080); C128 (the 80-col reality) =
44,474 always-resident + 8,424 play + 2,395 persist + 821 names =
56,114 B exactly. Overlays, C128 basis (this is the 80-column port):
29,254 B total, 4,088 B max slot — the C64 figures (28,002 / 4,068)
do not govern this port. Max tier payload: 5,368 B (C128 tier-cache
window).

Apple II gameplay-concurrent budget = 37,888 (resident) + window (holds
tier during gameplay). The Apple II has the smallest concurrent budget
of any port (C64 ~55.9K, C128 ~52.9K, Plus/4 ~55K, Apple II ~43.3K).
The equation M0 must close per-module, on paper, before any code:

```
always_resident + max(simultaneously swapped-in payloads) <= 37,888
    with reserve >= 1,500 B
every overlay payload <= 4,088 (C128 basis); tier payload <= 5,368 <= 5,376 window
aux: 1K text + 13,068 map + caches <= ~46K usable
```

Closure levers, all shipping architecture with in-tree precedent,
applied in order:

1. **OVL.STORAGE class** (new overlay ID; `OVL_MODAL_MISC` is the
   add-a-class pattern): save engine + disk-setup/restore UI leave
   resident (-3-4K est.).
2. **OVL.TITLE class**: title/menu/sysinfo flow, boot/death-restart only
   (-1.5-2.5K est.).
3. **Cold data to aux**: item-name/description token data, recall data —
   C128's `128.names` precedent (-1-3K est.).
4. **Play/persist swap slot (the structural closer — size TBD by M0)**:
   C128's mutually exclusive slot verbatim. A top-of-resident slot
   holds the dungeon-gameplay payload; modal/save phases overwrite it;
   a resident broker restores it before gameplay resumes, from an aux
   cache via AUXMOVE (~ms) instead of disk. The slot lives *inside*
   the 37,888 B resident region: it is not additive to the 43.3K
   concurrent figure — it converts always-resident bytes into swapped
   bytes. Against C128's ~58.3K gameplay-concurrent footprint
   (44,474 + 8,424 + 5,368 tier window) the raw gap is ~15K, so
   closure requires levers 1-3 landing mid-to-high estimates *plus*
   several KB of what C128 calls always-resident reclassified into the
   slot. The slot size is a reclassification budget M0 must validate
   against measured module sizes (8K bounds C128's 8,424 B play class,
   but the Apple II slot may need to absorb more) — not a demonstrated
   closure.

Per-module byte attribution is deliberately deferred to M0's measured
build; the lever set plausibly closes the aggregate gap, and
per-module closure is M0's gate.

### Aux Access Mechanics (NMOS-safe; the port's #1 correctness hazard)

RAMRD/RAMWRT (`$C002-$C005`) bank `$0200-$BFFF` only; `$0000-$01FF`
follows ALTZP (off). With RAMRD on, instruction fetches from
`$0200-$BFFF` come from aux — any aux-READ routine must execute from
ZP or the stack page.

- main-to-aux writes (boot preloads, map writes): RAMWRT on, normal
  resident loop, RAMWRT off. Writes-only switch, safe from ordinary
  code.
- aux-to-main reads: (a) per-byte map accessors = ~24 B thunk in
  platform ZP `$C0-$DF` (`sta $C003` / `lda (zp_map_ptr),y` /
  `sta $C002` / `rts`), installed at boot, reinstalled by the storage
  adapter after MLI sequences; (b) bulk copies = firmware AUXMOVE
  `$C311` (params at ZP `$3C-$43` collide with core player fields —
save/restore 8 bytes around each call). HIGH confidence on AUXMOVE
existence/params on IIe with internal C3 firmware; MODERATE on carry
polarity. Also pin INTC3ROM-vs-SLOTC3ROM selection (`$C00B`) for a
IIe with the 80-column card in slot 3, and AUXMOVE's register
clobbers — verify all in M0.
- Perf bounds: +~25 cycles per aux byte; full 78x19 redraw ~45 ms at
  1 MHz; dungeon-gen map writes ~+0.33 s/level. Acceptable.

## Zero-Page Strategy

No remap and no platform conditionals in `core/zeropage.s`. At runtime
the game uses no Applesoft, no Monitor, and runs SEI with no interrupt
sources (which also neutralizes the firmware-IRQ-clobbers-`$45`
hazard). Contention is handled by construction:

1. ProDOS MLI calls (driver ZP usage is version-dependent and
   deliberately not relied upon): the storage adapter saves/restores the
   full working window `$02-$EF` (238 B, ~4 ms) around every MLI
   sequence — core `$02-$8F` plus platform `$90-$EF` state, so no
   ProDOS version's high-ZP behavior can corrupt entropy counters, aux
   state, or thunk bytes — reusing the existing VOLATILE-zone
   caller-save pattern. Final architecture; the cost is invisible next
   to disk I/O. Narrowing back to `$02-$8F` is allowed only after
   verified MLI ZP usage (M0/M1 item); the thunk reinstall after MLI
   sequences stays regardless, as belt and braces.
2. AUXMOVE clobbers `$3C-$43`: the wrapper saves/restores 8 bytes.
3. Boot-time firmware init precedes core ZP init.

The C128-flavored labels above `$8F` (`$90`/`$C6`/`$CC`/`$D8`/`$FE`)
referenced by ~5 core sites are plain free RAM on the Apple II —
harmless. The platform claims `$90-$EF`. `tools/check_zp_usage.py`
continues to gate core.

## platforms/apple2/ File Inventory (all final implementations)

| File | Responsibility |
| --- | --- |
| `Makefile` | Self-contained build/run/disk/test targets; KickAss + AppleCommander auto-download rules (cx16 Makefile shape) |
| `main.s` | Linker script + entry: segmentdefs for resident payloads (C128-style splits per M0 table), all overlay segments (`outPrg`, start `$A600`, window max bounds), play/persist segments, `.const C128=false`/`PLUS4=false`, complete import cascade (clone c64 `main.s` order), title/menu flow, boundary `.assert`s |
| `boot.s` (`MORIA8.SYSTEM`) | ProDOS SYS entry at `$2000`: payloads will cover `$2000`, so stage the loader into the `$0200-$03CF` scratch block (loader + pathname + MLI param blocks <= 464 B; runs before any game state exists), MLI-READ all resident payloads into place, set TEXT/80COL/80STORE/ALTCHARSET, install ZP thunks, jump; exit = MLI QUIT |
| `config.s` | Game config consts (mirror `c64/config.s`) |
| `memory.s` | Memory-map constants + `.assert` guards; checker companion |
| `mmu_macros.s` | `MapRead_ptr0_y` etc. dispatching to `a2_map_read_ptr0` thunks (name required by core libdir import) |
| `memory_aux.s` | ZP thunk installer, RAMRD/RAMWRT primitives, AUXMOVE wrapper, `hal_memory_*` exports (enter/exit_os trivially correct on unbanked hardware; copy/read/write over aux switches), bank consts (`hal_memory_has_cpu_port=0`) |
| `vic_palette_consts.s` | `COL_*` logical color consts (name required by `core/color.s`) |
| `reu_stub.s` | Permanent inert REU symbols for the three core reference sites |
| `hal/hal_contract.s` | Shim importing `../../commodore/hal/hal_contract.s` (contracts + `HAL_STATUS_*`); resolved via `-libdir hal`. Flag: later promotion of contracts to `platforms/hal/` |
| `hal/layout.s` | 80x25, viewport 1,2,78x19, map 198x66 — clone `c128/hal/layout.s` values; adjust the three VDC-specific title flags |
| `hal/entropy_consts.s` | Four labels pointing at platform RAM counters (ticked in the input wait loop; seeded from keypress timing + optional `$C019` sample) |
| `hal/lifecycle_policy.s`, `hal/manifest.json` | Policy consts; manifest as documentation (c64 templates) |
| `screen_a2.s` | All 12 `hal_screen_*`: interleaved row addressing (base = `$400 + (row&7)*$80 + (row>>3)*$28`), even-column-aux via 80STORE+PAGE2, 256-byte C64-screen-code-to-Apple-char table (`sc<$20 -> (sc+$40)|$80`; `$20-$3F -> sc|$80`; inverse = drop `$80`, ALTCHARSET on), colorless policy: `set_color` records logical color, inverse reserved for reverse-space title attr; blank/unblank and begin/end_bulk are correct minimal implementations |
| `input.s` | All `hal_input_*`: `$C000`/`$C010` polling, ASCII-to-normalized-PETSCII table feeding `core/input_tables.s` (arrows `$08/$15/$0B/$0A` -> `$9D/$1D/$91/$11`; ESC = run-cancel/modal escape; shifted ASCII -> `$Cx` codes); `any_key_held` = read `$C010` bit 7 (IIe AKD — HIGH confidence IIe, verify IIc); entropy counters ticked here |
| `storage_mli.s` | The full ~100-export `hal_storage_*` surface: MLI adapters (OPEN/READ/WRITE/CLOSE/GET_FILE_INFO/SET_MARK/CREATE/DESTROY), ProDOS-error-to-`HAL_STATUS` map (`$46` NOT_FOUND, `$2B` WRITE_PROTECTED, `$48` DISK_FULL, `$27` ERR_UNKNOWN/IO, ...), phase + diag bytes, all filename labels (`OVL.*`, `MONSTER.DB.1-4`, `TITLE`, save/marker/score), blanket ZP save/restore + thunk reinstall |
| `save_stream.s` | Buffered byte-stream implementations of the KERNAL-shaped primitives (CHRIN/CHROUT/CHKIN/CHKOUT/SETNAM/SETLFS/OPEN/CLOSE/CLRCHN/READST) over MLI READ/WRITE + MARK — the permanent storage backend for `save.s` |
| `overlay_storage.s` | `overlay_load` backend: aux-cache fetch via AUXMOVE for cached classes, MLI read for on-demand classes, per the M0 cache manifest |
| `tier_storage.s` | Tier file MLI loads into the shared window; invalidation handshake (C64 semantics already in core) |
| `services.s` | `hal_sound_*` real speaker-click patterns at `$C030` mapped from the 42 semantic-ID call sites; `hal_irq_*` correct SEI-world implementations (no interrupt sources, so masking/ack are genuinely trivial, not stubbed); `hal_platform_*` lifecycle (init sets switches; panic prints status; shutdown = MLI QUIT) |
| `creature_data/creature_tiers.s`, `tier[1-4]_prg.s` | Wrappers importing `../../commodore/c64/creature_data/tierN.s` (cx16-verified pattern) |
| `compat/hal_storage_tier_test_stub.s` | Test-stub shim (name required by core import) |
| `check_memory_contract.py`, `tests/check_memory_contract_test.py` | Static gate over `.sym` + emitted binaries: payload spans, window bounds, `$BF00`/text-page/vector exclusions, aux-map spans, ZP-thunk residency; with selftest |
| `harness_smoke.py` | MAME driver (see Test Harness) |
| `docs/APPLE2_MEMORY_POLICY.md` | The M0 closure table + aux-access rules — the placement source of truth |

## Build Chain, Makefile, Boot Chain

- Kick emits PRG with a 2-byte header. New `tools/prg_to_bin.py` strips
  it and asserts the expected load address per payload (guards
  segment-start drift).
- AppleCommander (`ac.jar`) via `tools/applecommander/` auto-download
  mirroring the KickAss rule: `-pro140 moria8.po MORIA8` to create;
  insert `MORIA8.SYSTEM` as SYS/`$FF` and payloads/overlays/tiers/title
  as BIN/`$06` with auxtype = load address. HIGH confidence on
  capability, MODERATE on exact current CLI flags — pin and verify
  during M1 wiring. Fallback: cadius.
- Root Makefile: opt-in delegation exactly like cx16's verified pattern
  (`buildapple2 runapple2 diskapple2 testapple2 testapple2-smoke
  testapple2-runtime testapple2-memory-contract[-selftest]` delegate to
  `platforms/apple2`), kept out of default `all`/`build`/`test`.
- Kick invocation from `platforms/apple2/`:
  `-libdir ../../core -libdir . -libdir hal -define APPLE2`.
- Boot: ProDOS boots the `.po`, runs `MORIA8.SYSTEM` at `$2000`, which
  stages itself into the `$0200-$03CF` scratch block (its `$2000`
  origin is inside the resident payload span), MLI-READs each resident
  BIN to its home, sets soft switches, preloads aux caches (main-to-aux
  via RAMWRT, trivially safe), and jumps to entry. ProDOS 8 redistribution terms are MODERATE
  confidence — if unclear, require a user-supplied `PRODOS` file like
  the `KICKASS` override.
- Emulator-launching test targets run escalated on the first attempt
  (mirrors the VICE rule); static gates stay sandboxed.

## Storage/Save Decision (final)

Reuse `platforms/commodore/common/save.s` over buffered MLI stream
primitives, as permanent architecture. Basis: `save.s` (2,280 lines of
serialization/versioning/checksum/slot logic shared by three shipping
platforms) consumes storage exclusively through `hal_storage_*`
primitives (verified `save.s:55-56`). Raw byte-per-MLI-call would be
unsound; the shim is instead a buffered stream (MLI READ/WRITE on
fill/flush, sequential MARK) — a permanent, ordinary design with zero
impedance mismatch since ProDOS files are byte-addressable. cx16's
native rewrite was only natural on its restructured core; here it would
duplicate 2,280 lines for no gain.

Marker semantics: GET_FILE_INFO on `MORIA8.ID`; save volume = game
volume (or a `SAVES/` prefix); the two-drive swap UX degrades to
always-present probes — final behavior. Placement: OVL.STORAGE class
(M0 measures; if save + UI exceeds the window's 4,096 B code region,
split engine/UI into two classes — both final).

User decision needed: promote `save.s` to `platforms/shared/`
(recommended; mechanical, touches three platforms' imports) vs. a
documented cross-tree import (works today).

## Test Harness (MAME apple2e)

`harness_smoke.py`: Python parses `main.sym`, generates a per-scenario
Lua script (poll RAM sentinels via
`manager.machine.devices[':maincpu'].spaces['program']:read_u8()`, post
keys via `natkeyboard:post()`, print `ASSERT <name> PASS/FAIL`), runs
`mame apple2ee -autoboot_script t.lua -video none -sound none
-nothrottle -seconds_to_run N -flop1 moria8.po`, and parses stdout.
RAM-contract asserts, never pixels. One process per scenario; no
bidirectional protocol.

Flags: MAME Lua API names drift across releases (pin a MAME version;
MODERATE confidence on the exact API); aux-RAM peeks may need the aux
region rather than the CPU space (verified at M2 — the title scenario
asserts both text-page halves, which exercises exactly this); Apple IIe
ROMs are not redistributable — an `A2ROMS` env var is required,
skip-with-error like `X16EMU` handling. Manual-play fallback:
Virtual ][ (macOS) or real hardware.

## Milestones (full parity, hardest-problem-first)

### M0 — Placement closed on paper. No product code.

Run `make build` (existing platforms; sandboxed/static) and extract
per-module byte sizes from `-showmem`/`.sym` for C64 (40-col floor) and
C128 (80-col reality). Classify every core and platform module into
exactly one payload class (always-resident / each OVL.* including new
STORAGE and TITLE / play slot / persist slot / aux data / ProDOS
on-demand). Also pinned in M0: aux cache manifest; boot file list with
load order/addresses; ZP thunk addresses; AUXMOVE carry-polarity
verification; tier max size vs. the 8-byte window headroom (measure
`MONSTER.DB.*`; pre-decide the name-pool boundary shift rule, subject to
`tier_manager.s:525`'s name-blob assert); play/persist broker design
(C128 broker + five-facts checklist on paper).

Deliverable: `docs/APPLE2_MEMORY_POLICY.md` containing the closure
table. Gate: the closure equation closes per-module with >= 1,500 B
reserve; every measured byte assigned.

### M1 — Full build: complete HAL, complete cascade, everything links and fits.

The entire file inventory in final form; all HAL adapters real;
`main.s` with the complete import cascade covering all overlay classes
and play/persist segments per the M0 table; `.assert`s on every
boundary; contract checker + selftest; `prg_to_bin`; AppleCommander
wiring; root-Makefile delegation. No probe build, no partial cascade —
the full product link is gate zero.

Gate: `make buildapple2` assembles the entire game; every segment fits
its declared bounds; `testapple2-memory-contract` +
`check_zp_usage.py` + `check_6502_lint.py` green; `diskapple2` emits
the `.po`.

### M2 — Boot chain, first light.

`MORIA8.SYSTEM` boots the full binary to the rendered title on MAME.

Gate: `testapple2-runtime` boot scenario green — title asserted via
screen-RAM peeks in both main and aux text halves (retires the harness
aux-access risk before bring-up depends on it).

### M3 — Bring-up in dependency order, on the full build.

Fix real defects in final code; harness scenarios accrue cumulatively
against the same binary: input (key map, modal/escape, `$C010` AKD) ->
chargen (OVL.START, stat asserts) -> town (OVL.TOWN, tier load, stores)
-> dungeon gen (OVL.GEN, BFS-in-window-tail, aux-map integrity) ->
combat/monsters (tier switching, LOS) -> items/magic
(OVL.ITEMS/SPELL/UI) -> save/load (OVL.STORAGE, stream shims, roundtrip
state-equality + error-path status mapping). Every scenario is
permanent regression coverage.

Gate: full suite green end-to-end on one binary.

### M4 — Polish, performance, release.

Aux cache tuning within the M0 manifest (pure perf; correctness never
depended on it), speaker-click patterns across all 42 sound call sites,
title art, help/death/wizard verification, real-hardware/Virtual ][
pass, `ARCHITECTURE.md` + `CROSS_PLATFORM_STRATEGY.md` expansion
(reconcile two stale strategy points: the ca65 migration note — this
port retains Kick per in-tree precedent — and the claim that 128K
targets pre-load *all* overlays into extended memory, which this port
implements as a partial aux cache with disk-on-demand cold classes),
release `.po`.

Gate: full `testapple2` + `diskapple2` artifact + docs.

## Risks, Ranked by Late-Placement-Redesign Potential

1. **Per-module classification error causing resident overflow after
   code exists.** The #1 redesign-forcer. Retired in M0 (measured
   sizes, not estimates; 1,500 B reserve) and enforced forever at M1
   gate zero (`.assert`s + checker).
2. **Tier-vs-window headroom (5,368 vs. 5,376 = 8 bytes).** Boundary
   moves would ripple. Retired in M0: measure actual `MONSTER.DB.*`
   payloads; pre-decided pool-boundary shift rule. The overlay-slot
   headroom is equally tight (C128 max slot 4,088 vs. the 4,096 B
   window code region = 8 bytes); same retirement.
3. **Aux-read mechanism (RAMRD instruction-fetch trap).** A wrong
   mechanism poisons every map access and the broker. Retired in M0
   (thunk addresses + AUXMOVE polarity pinned, policy-doc rule, checker
   asserts thunk residency) and proven at M2 first light.
4. **Play/persist broker correctness** (gameplay payload restored
   before any gameplay code runs post-modal). Retired in M0 on paper
   (C128 broker + five-facts contract), asserted in M1, exercised by
   every M3 save/modal scenario.
5. **MLI/driver ZP or buffer interactions.** Retired by construction in
   M1: blanket `$02-$EF` save/restore + thunk reinstall around every
   MLI sequence.
6. **AppleCommander flags / SYS conventions / ProDOS redistribution.**
   Can stall M1/M2, never forces placement redesign. Verified during M1
   wiring; `PRODOS`-file env override if terms are unclear.
7. **MAME Lua drift / ROM licensing.** Harness-only blast radius.
   Pinned version, `A2ROMS` env, Virtual ][ fallback; proven at M2.
8. **80-col / aux-map performance at 1 MHz.** Bounded arithmetic says
   fine (~45 ms full redraw; ~+0.33 s/level gen); measured at M2/M3;
   any mitigation is local to `screen_a2.s`, never placement-level.

## Core/Common Residual Change List (near zero)

1. Zero core changes required to assemble — all name-bound imports are
   satisfied platform-side (`mmu_macros.s`, `vic_palette_consts.s`,
   `creature_data/`, `compat/`, `hal/hal_contract.s` shim,
   `reu_stub.s`, entropy RAM labels).
2. `core/zeropage.s`: no change. The single-remap-point design is the
   fallback if a real conflict ever surfaces; don't pre-pay.
3. `core/item_actions_overlay.s:340`: no change (false positive —
   item-ID compare).
4. User decision: promote `platforms/commodore/common/save.s` to
   `platforms/shared/` (recommended) vs. documented cross-tree import.
5. Optional M4 hygiene (user's call): extend
   `tools/check_hal_manifests.py` (hardcodes c64/c128/plus4; cx16 did
   not extend it — apple2's `manifest.json` can stand as
   documentation).
6. Budget for a handful of assembly-time residuals in shared files
   discovered only at the M1 full link; each reported individually as
   found, none anticipated to be structural.

## Explicit Gaps and Verification Items

- Per-module size attribution: deliberately deferred to M0's measured
  build (post-work16 merge).
- LOW/MODERATE-confidence hardware/OS claims, all scheduled for M0/M1
  verification: ProDOS LC `$D000` bank-2 availability (unused by this
  plan), AUXMOVE carry polarity + INTC3ROM selection + register
  clobbers, ProDOS 8 1.x vs 2.x `/RAM` creation behavior, MLI high-ZP
  (`$90-$EF`) usage (window narrowing only), `$C019` VBL polarity +
  IIc behavior (entropy garnish only), IIc `$C010` AKD, AppleCommander
  exact CLI flags, ProDOS redistribution terms, MAME Lua API surface.
- Title-art pipeline details (`core/title_data.s` platform define +
  80-col art source): sized but not designed; lands in M0
  classification + M4 polish.
