# Apple IIe Port Plan

Implementation plan for porting moria8 to the Apple IIe under
`platforms/apple2/`. This is the process document; the memory placement
source of truth is `docs/APPLE2_MEMORY_POLICY.md` (M0 complete, measured
at `f7d322d`). Where this plan and the policy doc disagree, the policy
doc wins.

## Status and Gating

**Gate satisfied: work16 merged as PR #47 (`f7d322d`); the merged tree
is byte-identical to the work16 tip (`git diff work16 origin/main` is
empty).** M0 measurement ran against that tree and produced
`docs/APPLE2_MEMORY_POLICY.md`. (Branch `work15` merged earlier as PR
#46.)

Open hardware/tooling verification items (formerly the pre-merge list):

- AUXMOVE ($C311) carry polarity, parameter behavior, INTC3ROM-vs-
  SLOTC3ROM selection ($C00B), and register clobbers — OPEN: firmware,
  not covered by the ProDOS TRM; the MAME spike verifies, and the M2
  boot scenario proves it empirically regardless
- MAME `apple2ee` Lua memory-peek spike (main and aux RAM) — OPEN
- AppleCommander CLI — VERIFIED (ac 13.2 docs): `-pro140 <img> <vol>`
  creates; `-p <img> <name> <type> [0xaddr]` puts stdin with auxtype =
  load address (`sys`/`bin` types). Gotcha: replace requires delete
  first, so `diskapple2` recreates the image per build
- ProDOS redistribution — RESOLVED (policy): 2.4.3 is freely
  distributed at prodos8.com (John Brooks) but carries no explicit
  license text; ship without `PRODOS` and require a user-supplied file
  (like the `KICKASS` override), source documented
- `tools/prg_to_bin.py` — DONE

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
- `platforms/shared/save.s` — storage primitive surface
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

**Superseded by `docs/APPLE2_MEMORY_POLICY.md` (M0, measured).** The
tables below reflect the M0 revisions; the policy doc is authoritative
for per-module placement, the closure ledger, and the aux manifest.

### Main RAM

| Range | Size | Owner |
| --- | ---: | --- |
| `$0000-$00FF` | 256 | ZP: core keeps `$02-$8F` unchanged; platform owns `$90-$EF` (state, 4 entropy counter bytes, two 16 B aux-read thunks at `$C0-$DF`); `$F0-$FF` reserved |
| `$0100-$01FF` | 256 | Stack |
| `$0200-$03CF` | 464 | Platform scratch: ZP save buffer (142 B), MLI parameter blocks, loader state |
| `$03D0-$03FF` | 48 | ProDOS/reset/IRQ vectors — reserved |
| `$0400-$07FF` | 1,024 | 80x24 text page, main half (odd columns); screen holes (`$x78-$x7F`) never touched |
| `$0800-$09FF` | 512 | Floor-item table (256) + creature scratch (256) — core raw-addressed |
| `$0A00-$7BFF` | 29,184 | Always-resident region (multiple Kick segments, C128-style splits) |
| `$7C00-$9DFF` | 8,704 | Play/modal slot: play payload (8,430) during gameplay; OVL.STORAGE / OVL.TITLE payloads overwrite it in modal phases; broker restores play from aux cache via AUXMOVE with signature validation |
| `$9E00-$A1FF` | 1,024 | Tier name pool (`PLATFORM_TIER_NAME_POOL_BASE=$9E00`) — core raw-addressed; need 808 B (tier-4 blob), assert margin 216 B |
| `$A200-$BAFF` | 6,144 | Shared overlay/tier window (`BANKED_DATA_BASE`); C64 mutually-exclusive semantics unchanged (`overlay_load` invalidates tier). Overlay code region `$A200-$B3FF` (4,608 >= max overlay 4,090; 518 B spare); tier mode may use the whole window (max tier 2,062); no BFS allocation — connectivity is queue-less (`dungeon_gen.s:2384+`) |
| `$BB00-$BEFF` | 1,024 | ProDOS MLI file I/O buffer (page-aligned, one open file) |
| `$BF00-$BFFF` | 256 | ProDOS global page (MLI entry `JSR $BF00`) |

The C64 RuntimeBanked class (`$F000`, 4,080 B) disappears as a class:
there is no ROM shadow on the Apple II, so its content is ordinary
resident bytes already inside the 51,481 B figure. Language Card RAM is
not used — VERIFIED against the ProDOS 8 TRM (§3.3 Figure 3-1): the
MLI itself resides in the main LC (`$D000-$FFFF`), and aux LC is
partially used by ProDOS/BASIC.SYSTEM. The system bit map (§3.3.3)
protects only pages 0, 1, 4-7, and BF; our `$BB00` I/O buffer is
supplied per-OPEN and marked normally — no conflict by construction.

### Aux RAM (behind accessors only; ALTZP stays off)

| Range | Size | Owner |
| --- | ---: | --- |
| aux `$0400-$07FF` | 1K | Text page aux half (even columns) |
| aux `$0800-$3B0B` | 13,068 | Live map, 198x66 (mirrors C128 layout values) — all access via thunked MapRead/MapWrite |
| aux `$3B0C-$4FFF` | 5,108 | Aux data (M0 lever L3): item names 821 + huffman_data 2,911 + store_data 811 + recall 289 = 4,832 used |
| aux `$5000-$BFFF` | 28,672 | Hot cache: play 8,430 + ovl.town/ui/items/death/gen = 28,587 used (85 B spare). Cold classes (START, HELP, MODAL, DISARM, STORAGE, TITLE, tiers, title art) stay disk-on-demand — disk-speed loads are the stock-C64 norm |

ProDOS 8 1.x on a 128K machine auto-creates the `/RAM` volume in aux
memory spanning roughly aux `$0800-$BFFF` — exactly the map+cache
region above. Policy: the game never issues I/O to `/RAM` (overwriting
aux is then safe; standard 128K practice), and boot may deallocate it.
The `/RAM` driver and quit dispatcher live in aux LC `$D000-$FFFF`,
which is why the LC stays out of scope above. ProDOS 8 1.x vs 2.x
`/RAM` creation behavior is an M0 verification item.

### Closure Arithmetic (M0 result — policy doc holds the full ledger)

M0 measured post-work16 content (`build/` artifacts at `f7d322d`):
C128 gameplay-concurrent = 44,971 always-resident + 8,430 play =
53,401 B. Overlays: 29,580 B total, max slot 4,090 (ovl.gen). Tier
payloads: 830 / 1,109 / 1,367 / 2,062 — the 5,368 B figure cited
pre-M0 was the C128 tier-window reservation, not a payload.

Apple II concurrent budget: 29,184 (always region) + 8,704 (play slot)
= 37,888, with a >= 1,500 B aggregate reserve requirement. Raw gap
vs. C128: ~17K.

**Finding: the original levers 1-3 below (est. 5.5-9.5K) do not close
this gap, and the slot cannot help — it lives inside the resident
region, so reclassification leaves the concurrent sum unchanged (slot
invariance). Only aux-data moves, overlay-class moves, and net
platform shrink reduce the sum.** Closure is achieved on paper only
with the expanded mandatory package in `docs/APPLE2_MEMORY_POLICY.md`
(levers L2-L7 plus remediation R1-R4: item_commands/wizard/ego to
overlay classes and platform-budget tightening; R5 and the Language
Card held in reserve), landing at 1,608 B aggregate margin on
estimates. M1 gate zero converts every estimate into a hard assert.

```
always_resident <= 29,184;  play/modal slot = 8,704;  reserve >= 1,500
every overlay payload <= 4,090 (measured); tier payload <= 2,062
    window code region 4,608; tier mode may use the full 6,144 window
aux: 1K text + 13,068 map + 4,832 data + 28,587 hot cache <= ~46K usable
```

The per-lever byte ledger (L2-L7, R1-R5) and the per-module
classification are in the policy doc. Historical lever descriptions:

1. **OVL.STORAGE class** (new overlay ID; `OVL_MODAL_MISC` is the
   add-a-class pattern): save engine + disk-setup/restore UI leave
   resident. M0 outcome: slot-hosted at `$7C00` (overwrites play),
   est. ~4,100 B; the persist class as such disappears into it.
2. **OVL.TITLE class**: title/menu/sysinfo flow, boot/death-restart
   only. M0 outcome: slot-hosted, est. ~2,000 B.
3. **Cold data to aux**: item names, huffman_data, store_data, recall —
   C128's `128.names` precedent. M0 outcome: 4,832 B at aux
   `$3B0C-$4FFF` (lever L3), plus L4 (ui string data, est. 1,500).
4. **Play swap slot**: C128's mutually exclusive slot verbatim, at
   `$7C00-$9DFF` (8,704 B; play payload 8,430 measured). M0 confirmed
   slot invariance: the slot hosts modal payloads and enables the
   ~100 ms AUXMOVE restore, but does not shrink the concurrent sum.

M0's per-module classification assigns every measured byte; closure
holds at 1,608 B aggregate margin with remediation levers R1-R4
applied (policy doc, "Closure Equation").

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
- Perf bounds: +~25 cycles per aux byte; full 78x18 redraw ~43 ms at
  1 MHz; dungeon-gen map writes ~+0.33 s/level. Acceptable.

## Zero-Page Strategy

No remap and no platform conditionals in `core/zeropage.s`. At runtime
the game uses no Applesoft, no Monitor, and runs SEI with no interrupt
sources (which also neutralizes the firmware-IRQ-clobbers-`$45`
hazard). Contention is handled by construction:

1. ProDOS MLI calls: the storage adapter saves/restores the core
   window `$02-$8F` (142 B, ~2 ms) around every MLI sequence,
   reusing the existing VOLATILE-zone caller-save pattern. Verified
   against the ProDOS 8 TRM (§3.3.1): the MLI uses `$40-$4E` (restored
   per call) and its disk driver uses `$3A-$3F` (not restored) — the
   whole MLI ZP footprint is inside the core window, high ZP is never
   touched. The thunk reinstall after MLI sequences stays as belt and
   braces. Final architecture; the cost is invisible next to disk I/O.
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
| `main.s` | Linker script + entry: resident `$0A00-$7BFF`, load-once play `$7C00-$9FFF`, tier-name pool `$A000-$A3FF`, and all overlay segments at `$A400-$B9FF`; complete import cascade, title/menu flow, boundary and cache-slot `.assert`s |
| `boot.s` (`MORIA8.SYSTEM`) | ProDOS SYS entry at `$2000`: payloads will cover `$2000`, so stage the loader into the `$0200-$03CF` scratch block (loader + pathname + MLI param blocks <= 464 B; runs before any game state exists), MLI-READ all resident payloads into place, set TEXT/80COL/80STORE/ALTCHARSET, install ZP thunks, jump; exit = MLI QUIT |
| `config.s` | Game config consts (mirror `c64/config.s`) |
| `memory.s` | Memory-map constants + `.assert` guards; checker companion |
| `mmu_macros.s` | `MapRead_ptr0_y` etc. dispatching to `a2_map_read_ptr0` thunks (name required by core libdir import) |
| `memory_aux.s` | ZP thunk installer, RAMRD/RAMWRT primitives, AUXMOVE wrapper, `hal_memory_*` exports (enter/exit_os trivially correct on unbanked hardware; copy/read/write over aux switches), bank consts (`hal_memory_has_cpu_port=0`) |
| `vic_palette_consts.s` | `COL_*` logical color consts (name required by `core/color.s`) |
| `reu_stub.s` | Permanent inert REU symbols for the three core reference sites |
| `hal/hal_contract.s` | Shim importing `../../commodore/hal/hal_contract.s` (contracts + `HAL_STATUS_*`); resolved via `-libdir hal`. Flag: later promotion of contracts to `platforms/hal/` |
| `hal/layout.s` | 80x24: message rows 0-1, viewport 1,2,78x18, input row 20, status rows 21-23, map 198x66; the Apple layout must not synthesize a C128-only row 24 because its address aliases text-page screen holes and row 1 |
| `hal/entropy_consts.s` | Four labels pointing at platform RAM counters (ticked in the input wait loop; seeded from keypress timing + optional `$C019` sample) |
| `hal/lifecycle_policy.s`, `hal/manifest.json` | Policy consts; manifest as documentation (c64 templates) |
| `screen_a2.s` | All 12 `hal_screen_*`: interleaved row addressing (base = `$400 + (row&7)*$80 + (row>>3)*$28`), even-column-aux via 80STORE+PAGE2, 256-byte C64-screen-code-to-Apple-char table (`sc<$20 -> (sc+$40)|$80`; `$20-$3F -> sc|$80`; inverse = drop `$80`, ALTCHARSET on), colorless policy: `set_color` records logical color, inverse reserved for reverse-space title attr; blank/unblank and begin/end_bulk are correct minimal implementations |
| `input.s` | All `hal_input_*`: `$C000`/`$C010` polling, ASCII-to-normalized-PETSCII table feeding `core/input_tables.s` (arrows `$08/$15/$0B/$0A` -> `$9D/$1D/$91/$11`; ESC = run-cancel/modal escape; shifted ASCII -> `$Cx` codes); `any_key_held` = read `$C010` bit 7 (IIe AKD — HIGH confidence IIe, verify IIc); entropy counters ticked here |
| `storage_mli.s` | The full ~100-export `hal_storage_*` surface: MLI adapters (OPEN/READ/WRITE/CLOSE/GET_FILE_INFO/SET_MARK/CREATE/DESTROY), ProDOS-error-to-`HAL_STATUS` map (`$46` NOT_FOUND, `$2B` WRITE_PROTECTED, `$48` DISK_FULL, `$27` ERR_UNKNOWN/IO, ...), phase + diag bytes, all filename labels (`OVL.*`, `MONSTER.DB.1-4`, `TITLE`, save/marker/score), blanket ZP save/restore + thunk reinstall |
| `save_stream.s` | Buffered byte-stream implementations of the KERNAL-shaped primitives (CHRIN/CHROUT/CHKIN/CHKOUT/SETNAM/SETLFS/OPEN/CLOSE/CLRCHN/READST) over MLI READ/WRITE + MARK — the permanent storage backend for `save.s` |
| `overlay_storage.s` | `overlay_load` backend: aux-cache fetch via AUXMOVE for cached classes, MLI read for on-demand classes, per the M0 cache manifest |
| `cache_layout.s` | Single source of truth for the page-aligned boot/runtime aux-cache manifest; imported by both `boot.s` and `overlay_storage.s` |
| `tier_storage.s` | Tier file MLI loads into the shared window; invalidation handshake (C64 semantics already in core) |
| `services.s` | `hal_sound_*` real speaker-click patterns at `$C030` mapped from the 42 semantic-ID call sites; `hal_irq_*` correct SEI-world implementations (no interrupt sources, so masking/ack are genuinely trivial, not stubbed); `hal_platform_*` lifecycle (init sets switches; panic prints status; shutdown = MLI QUIT) |
| `creature_data/creature_tiers.s`, `tier[1-4]_prg.s` | Wrappers importing `../../commodore/c64/creature_data/tierN.s` (cx16-verified pattern) |
| `compat/hal_storage_tier_test_stub.s` | Test-stub shim (name required by core import) |
| `check_memory_contract.py --selftest` | Static gate over `.sym` addresses and emitted PRG headers/extents, with built-in negative fixtures. Assembler assertions remain the authoritative placement gate; this independently checks that emitted artifacts match their linked owners. |
| `harness_smoke.py` | MAME driver (see Test Harness) |
| `docs/APPLE2_MEMORY_POLICY.md` | The M0 closure table + aux-access rules — the placement source of truth |

## Build Chain, Makefile, Boot Chain

- Kick emits PRG with a 2-byte header. New `tools/prg_to_bin.py` strips
  it and asserts the expected load address per payload (guards
  segment-start drift).
- AppleCommander (`ac.jar`) via `tools/applecommander/` auto-download
  mirroring the KickAss rule: `-pro140 moria8.po MORIA8` to create;
  `-p moria8.po <NAME> sys 0x2000` / `bin 0x<addr>` to insert payloads
  (auxtype = load address). VERIFIED against the ac 13.2 docs; pin the
  version during M1 wiring. ac requires delete-before-replace, so
  `diskapple2` recreates the image per build. Fallback: cadius.
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
  via RAMWRT, trivially safe), and jumps to entry. The `PRODOS` kernel
  file is user-supplied (2.4.3 from prodos8.com; no explicit license
  text, so it is not vendored — same pattern as the `KICKASS`
  override).
- Emulator-launching test targets run escalated on the first attempt
  (mirrors the VICE rule); static gates stay sandboxed.

## Storage/Save Decision (final)

Reuse `platforms/shared/save.s` (promoted from
`platforms/commodore/common/`; move verified byte-identical across all
65 build artifacts) over buffered MLI stream
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
always-present probes — final behavior. Placement: OVL.STORAGE class,
slot-hosted at `$7C00` (overwrites play; broker restores it after).
M0 outcome: est. ~4,100 B <= 8,704 B slot — fits as one class, no
engine/UI split needed.

`save.s` now lives at `platforms/shared/save.s` (user-approved
promotion; verified byte-identical). apple2 imports it from there.

## Test Harness (MAME apple2e)

`harness_smoke.py`: Python parses `main.sym`, generates a per-scenario
Lua script (poll RAM sentinels via
`manager.machine.devices[':maincpu'].spaces['program']:read_u8()`, post
keys via `natkeyboard:post()`, print `ASSERT <name> PASS/FAIL`), runs
`mame apple2ee -autoboot_script t.lua -video none -sound none
-nothrottle -seconds_to_run N -flop1 moria8.po`, and parses stdout.
RAM-contract asserts, never pixels. One process per scenario; no
bidirectional protocol. Both the harness and `make runapple2` route MAME's
configuration, NVRAM, input, state, snapshot, diff, comment, and share output
under `build/apple2/mame/`; direct emulator launches remain covered by the
repository ignore rules.

Flags: MAME Lua API names drift across releases (pin a MAME version;
MODERATE confidence on the exact API); aux-RAM peeks may need the aux
region rather than the CPU space (verified at M2 — the title scenario
asserts both text-page halves, which exercises exactly this); Apple IIe
ROMs are not redistributable — an `A2ROMS` env var is required,
skip-with-error like `X16EMU` handling. Manual-play fallback:
Virtual ][ (macOS) or real hardware.

## Milestones (full parity, hardest-problem-first)

### M0 — Placement closed on paper. No product code. **COMPLETE.**

Outcome (`f7d322d`): `docs/APPLE2_MEMORY_POLICY.md` delivered. The gate
result: the equation closes per-module at 1,608 B aggregate margin —
only with the expanded lever package (L2-L7) plus remediation levers
R1-R4 applied; R5 (tables.s to aux) and the Language Card are held in
reserve as the M1 bust escape hatches. Key surprises: original levers
1-3 insufficient (raw gap ~17K, not ~9.6K); slot invariance means the
slot never reduces the concurrent sum; tier payloads max 2,062 B
(risk #2 dissolved); ovl.gen grew to 4,090 post-work16; C64
connectivity is queue-less (no BFS allocation). Original M0 scope,
for the record:

Run `make build` (existing platforms; sandboxed/static) and extract
per-module byte sizes from `-showmem`/`.sym` for C64 (40-col floor) and
C128 (80-col reality). Classify every core and platform module into
exactly one payload class (always-resident / each OVL.* including new
STORAGE and TITLE / play slot / persist slot / aux data / ProDOS
on-demand). Also pinned in M0: aux cache manifest; boot file list with
load order/addresses; ZP thunk addresses; AUXMOVE carry-polarity
verification (carried to M1 — no emulator run yet); tier max size vs.
window headroom (measured `MONSTER.DB.*`; name pool set to 1,024 B per
`tier_manager.s:525`'s name-blob assert); play/persist broker design
(C128 broker + five-facts checklist, in the policy doc).

Deliverable: `docs/APPLE2_MEMORY_POLICY.md` containing the closure
table. Gate: the closure equation closes per-module with >= 1,500 B
reserve; every measured byte assigned. **Met, with the R1-R4 caveat
above.**

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

Status (achieved): boot_title 7/7 green and repeatable; `N` (via
`A2_DEBUG_AUTONEW`) reaches the chargen race menu, halted only by the
keyboard-ROM harness blocker. Boot rides a single-open sequential
MORIA8.PAK container (see memory policy Boot File List): ProDOS 2.4.3's
Disk II driver under MAME 0.288 loses the head after several rapid
OPEN/GFI/READ/CLOSE cycles (deterministic per image layout; reproduced
with a 346-byte loader reading 15 tiny files — 12 pass, 13th hangs).
Two latent defects fixed by the same redesign: the aux cache v4 slots
silently truncated four outgrown overlays (TOWN/ITEMS/SPELL/MODAL), and
`title_menu_str` lived in the unloaded play slot (moved
`runtime_ui_strings.s` back to resident per its own contract).

### M3 — Bring-up in dependency order, on the full build.

Fix real defects in final code; harness scenarios accrue cumulatively
against the same binary: input (key map, modal/escape, `$C010` AKD) ->
chargen (OVL.START, stat asserts) -> town (OVL.TOWN, tier load, stores)
-> dungeon gen (OVL.GEN, queue-less connectivity, aux-map integrity) ->
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
2. **Tier-vs-window headroom — dissolved by M0.** Measured tier
   payloads max 2,062 B vs. the 6,144 B window; the pre-M0 5,368 figure
   was the C128 window reservation, not a payload. Overlay headroom
   after the M0 window move: 4,608 − 4,090 = 518 B, asserted at M1
   gate zero.
3. **Aux-read mechanism (RAMRD instruction-fetch trap).** A wrong
   mechanism poisons every map access and the broker. Retired in M0
   (thunk addresses + AUXMOVE polarity pinned, policy-doc rule, checker
   asserts thunk residency) and proven at M2 first light.
4. **Play-slot broker correctness** (gameplay payload restored before
   any gameplay code runs post-modal). Retired in M0 on paper (C128
   broker + five-facts contract, applied in the policy doc; modal
   payloads are slot-hosted and play restores from aux cache via
   AUXMOVE with signature validation), asserted in M1, exercised by
   every M3 save/modal scenario.
5. **MLI/driver ZP or buffer interactions.** Retired by construction in
   M1: blanket `$02-$8F` save/restore + thunk reinstall around every
   MLI sequence; MLI ZP footprint (`$3A-$4E`) verified against the
   ProDOS 8 TRM §3.3.1.
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
4. Done: `save.s` promoted to `platforms/shared/` (user-approved;
   byte-identical rebuild across c64/c128/plus4).
5. Optional M4 hygiene (user's call): extend
   `tools/check_hal_manifests.py` (hardcodes c64/c128/plus4; cx16 did
   not extend it — apple2's `manifest.json` can stand as
   documentation).
6. Budget for a handful of assembly-time residuals in shared files
   discovered only at the M1 full link; each reported individually as
   found, none anticipated to be structural.

## Explicit Gaps and Verification Items

### M3 aux-data and overlay repair record — 2026-07-21

```text
Problem and success criteria:
Apple gameplay corrupted resident/overlay code because aux-owned store and recall state was accessed as main RAM, aux cache slots overlapped after overlay growth, and inventory selection could return into a replaced overlay. Success is complete aux routing for moved blocks, non-overlapping cache payloads, valid save/load bank dispatch, restored caller overlays, and all linked regions inside their asserted owners.

State being changed:
Placement/access mechanics for store inventory, monster recall, class-spell and lookup tables, item-name/Huffman streams, overlay-cache manifests, and selector return state. Gameplay values and formulas are unchanged.

Search scope and terms:
All core/Apple readers and writers of si_*, recall_*, class_spell_*, mage/priest/rogue/ranger/paladin spell tables, spell mask tables, book metadata, store lookup tables, A2 cache constants, piw_return_overlay, save block descriptors, RAMRD/RAMWRT thunks, and overlay window literals.

Relevant readers/writers found and known exclusions:
Store init/restock/store/home/UI, monster combat/magic/recall UI, character and player-magic flows, shared save block tables, item-name/Huffman decoders, and boot/runtime overlay loading were included. hg_kicked and store_base_idx remain main-resident intentionally because they are small cross-overlay hot state. Runtime conversion of all cold files into a persistent PAK handle is excluded: the proposed ProDOS/MAME degradation cause is not established by product-memory evidence.

Initialization, reset and persistence points:
store_init_all clears all seven contiguous aux store arrays; recall retains its existing meta-game lifetime; save/load classifies the complete store-array span plus the recall block as aux; boot preloads A2.AUXDATA and the six cache payloads from MORIA8.PAK.

Affected production sequence through the changed transition:
Boot PAK -> aux data/cache copies -> A2.PLAY load -> new-game store init -> town/store reads and writes; spell/prayer or study -> ITEMS selector -> optional HELP/UI modal -> ITEMS restoration -> SPELL restoration; save/load descriptor -> main-or-aux byte stream dispatch.

Contract decision or selected upstream oracle with source locations:
docs/APPLE2_MEMORY_POLICY.md ownership rules; platforms/apple2/memory_aux.s RAMRD/RAMWRT thunk contract; platforms/shared/save.s descriptor order; core/player_items.s overlay-return contract; assembler boundaries in platforms/apple2/main.s.

Intentional Moria8 deviations:
N/A — representation and platform loading only; no gameplay behavior is changed.

Input/intermediate widths, signedness, carry, range and overflow policy:
Aux addresses and lengths are 16-bit; store arrays are seven contiguous 96-byte blocks; recall is one 260-byte block; boot cache copies round payload lengths up to pages. Selector carry remains success/cancel and is preserved across overlay reload. Cache slot sizes are link-time checked against exact payload extents.

RNG reduction and bias, if applicable:
N/A — no RNG formula changed.

Affected platforms, overlays, banks and owners:
Apple main/aux RAM, A2.PLAY, TOWN/UI/ITEMS/SPELL/MODAL and STORAGE save paths. Shared-source changes retain direct Commodore accesses; C64, C128, and Plus/4 parity builds/runtime checks apply. C128 world remains below $8CA0 after Apple-only helper expansion was gated to Apple.

Required production-path tests:
Apple full build and disk image; Apple link/cache assertions; HAL/ZP/lint gates; C64 store/item/effects/combat/monster-attack production tests; C128 authoritative suite plus focused main_loop128; Plus/4 new-game-to-town and overlay-load tests; MAME Apple boot/new-game/store/spell/save scenarios when A2ROMS is available.

Known behavior explicitly out of scope:
Persistent runtime MORIA8.PAK refactor, ProDOS version policy, unrelated test-harness path repairs, and gameplay balance/semantics.

Unresolved uncertainty and risk:
Apple runtime is not re-executed in this environment because A2ROMS is unset. The declared Apple memory-contract checker is also absent, so its Make target cannot run; 291 main-image assembler assertions currently provide the executable placement gate. OVL.ITEMS has zero byte headroom and A2.PLAY has 41 bytes, so future growth must move owned code/data rather than relax limits.
```

### M3 town-entry screen-hole repair record — 2026-07-21

```text
Problem and success criteria:
The initial town viewport became visible and then execution stopped before the status/message UI completed. The Apple layout advertised a nonexistent 25th text row; the first operation in status_draw cleared INPUT_ROW 24 at computed address $0478, writing the firmware/ProDOS screen hole and then physical row 1. Success is that every screen row accepted by the Apple backend is a real row 0-23 and no full-screen, status, or modal path computes row 24.

State being changed:
Apple physical screen geometry only: SCREEN_ROWS becomes 24, the viewport becomes 18 rows, and row 20 becomes INPUT_ROW. Shared modal footer/border row constants derive from SCREEN_ROWS instead of assuming 25 rows. Gameplay and turn state are unchanged.

Search scope and terms:
hal_layout_screen_rows, hal_layout_input_row, SCREEN_ROWS, INPUT_ROW, literal display row 24, screen_clear, screen_clear_row, screen_set_cursor, ui_status, help, inventory, equipment, spell list, death/high-score screen, and Apple text-page row arithmetic.

Relevant readers/writers found and known exclusions:
Apple screen clear/row tables; status and game-loop input-row clears; full-screen help clear; help frame/content; inventory/equipment/spell footers; death prompt and high-score rows. Other literal 24 uses were inspected and excluded where they are item IDs, RNG ranges, arithmetic widths, or gameplay caps. Store message rows 20-23 are valid physical rows and remain unchanged.

Initialization, reset and persistence points:
Screen geometry is compile-time state. screen_clear and ui_clear_full_screen_safe now iterate exactly rows 0-23. No persisted save representation changes.

Affected production sequence through the changed transition:
New game -> town generation -> render viewport rows 2-19 -> screen unblank -> status_draw -> clear INPUT_ROW 20 -> draw status rows 21-23 -> welcome message -> main loop. Modal full clears and footer draws use the same 24-row bound.

Contract decision or selected upstream oracle with source locations:
Apple II 40/80-column text has 24 physical rows; platforms/apple2/screen_a2.s owns the interleaved row formula and docs/APPLE2_MEMORY_POLICY.md forbids writes to $x78-$x7F screen holes. core UI code consumes platform SCREEN_ROWS/INPUT_ROW.

Intentional Moria8 deviations:
Apple uses an 18-row viewport so its two message rows, command-input row, and three status rows remain distinct on a 24-row display. Commodore retains its 19-row viewport and row-24 input/footer layout byte-for-byte.

Input/intermediate widths, signedness, carry, range and overflow policy:
Row indices are unsigned bytes. Valid Apple rows are 0-23; assembler assertions enforce INPUT_ROW < 24, viewport end <= input, input < status start, and status start + 2 < 24.

RNG reduction and bias, if applicable:
N/A — no RNG path changed.

Affected platforms, overlays, banks and owners:
Apple resident screen/status code and HELP/UI/DEATH/SPELL modal presentation. Shared source substitutes SCREEN_ROWS-1 for literal 24; it assembles to the original value on C64, C128, and Plus/4.

Required production-path tests:
Apple full build and disk image with layout assertions; cross-platform full build; Apple new-game-to-town runtime must show all three status rows and accept input without a row-24 write. Help/inventory/equipment/spell/death modal footer checks remain required when the Apple runtime harness is available.

Known behavior explicitly out of scope:
Persistent runtime PAK conversion, ProDOS version changes, emulator-driver workarounds, and unrelated MAME harness infrastructure.

Unresolved uncertainty and risk:
The exact stopped PC from the reported run was not captured, and Apple runtime cannot be executed in this environment because A2ROMS is unset. The illegal $0478 write is independently proven from the production address formula and occurs exactly at the observed post-viewport transition; runtime confirmation remains required before calling the town hang closed.
```

### M3 character-selection key-release repair record — 2026-07-21

```text
Problem and success criteria:
After accepting the sex selection, the Apple build remained on that screen while the PC repeatedly visited the input polling helpers near $0E2A. input_wait_release waited without a bound for the IIe any-key-down signal to clear, so an emulator-lost key-up event could deadlock the transition. Success is that the normal release path retains its two clean polls, an indefinitely asserted signal cannot stop progress, and the player-facing prompt uses the game's established term "sex".

State being changed:
Apple keyboard transition handling only. No character attributes, save data, selection values, or RNG state change. The shared prompt text changes from "Choose your gender" to "Choose your sex"; the existing Male/Female choices and internal symbol names are unchanged.

Search scope and terms:
create_select_gender, create_gender_title, hal_input_wait_release, input_wait_release, modal_prepare, A2_KBD, A2_KBDSTRB, AKD, $C000, $C010, and the rebuilt $0E2A-$0E6F symbols.

Relevant readers/writers found and known exclusions:
Character creation calls hal_input_wait_release after a valid A/B choice and before redrawing the summary. Apple modal preparation and other one-shot prompts use the same routine. input_get_key and input_run_key_held were inspected but are unchanged. Character-sheet "Sex" output was already correct.

Initialization, reset and persistence points:
The wait uses only temporary X/Y counters and preserves both registers. It creates no persistent state. The keyboard strobe is cleared while polling and once more on the exceptional timeout path.

Affected production sequence through the changed transition:
Sex screen -> accept A/B -> input_wait_release -> character summary redraw -> dismissal wait -> remaining character creation. On a normal key-up, two consecutive clean keyboard polls are still required. If AKD remains continuously asserted for the bounded interval, the routine clears the strobe and permits the transition.

Contract decision or selected upstream oracle with source locations:
Apple IIe Technical Reference keyboard soft-switch definitions for $C000/$C010; MAME apple2e.cpp AY-3600 any-key-down and repeat handling; platforms/apple2/input.s HAL implementation; core/player_create.s selection flow.

Intentional Moria8 deviations:
The exceptional Apple path no longer guarantees that no physical key is held when hal_input_wait_release returns. This is deliberately bounded to avoid a permanent emulator/input deadlock; the ordinary hardware path retains the existing release semantics.

Input/intermediate widths, signedness, carry, range and overflow policy:
The timeout is an unsigned nested 8-bit X/Y poll count. X wraps 16 times before fallback. The routine preserves X and Y and makes no carry-result promise, matching its existing callers.

RNG reduction and bias, if applicable:
N/A — input polling continues to feed the existing entropy tick, but no RNG reduction or gameplay formula changes.

Affected platforms, overlays, banks and owners:
Apple resident input code and the shared character-creation prompt. Commodore input implementations are unchanged; their assembled prompt changes by three bytes only.

Required production-path tests:
Cross-platform full build; Apple disk build and link assertions; Apple runtime character creation must advance after selecting sex both on normal release and under the reported emulator behavior. Runtime confirmation remains required because this environment lacks the Apple II ROM set.

Known behavior explicitly out of scope:
Changing internal create_gender_* symbols, expanding character-sex choices, emulator configuration changes, persistent runtime PAK conversion, and unrelated input semantics.

Unresolved uncertainty and risk:
No live $C010 trace was captured from the user's failing run, so the stuck-AKD diagnosis is an inference from the unchanged screen, polling PC range, and MAME's implementation. The bounded fallback is defensive and Apple-only. A real held key can therefore be treated as released after the timeout and may be consumed by a later prompt; runtime retest is the remaining gate.
```

### M3 player-glyph renderer-loop repair record — 2026-07-21

```text
Problem and success criteria:
Town rendering stopped when the full viewport reached the player cell. A 50,000-instruction Virtual ][ trail proved an infinite loop at rv_apply_player_override ($61AE-$61C4): SC_PLAYER is screen code $00, so the BNE used as an unconditional exit after loading it was never taken. The blank path then jumped back to the same override. Success is an unconditional exit after staging the player glyph in both full and single-tile renderers.

State being changed:
Apple renderer control flow only. Tile, player, visibility, viewport, map, and display-code representations are unchanged.

Search scope and terms:
The complete Virtual ][ instruction trail and snapshot; $61AE-$61C4; rv_apply_player_override; rst_apply_player_override; SC_PLAYER; draw_blank; write_tile; all lda #SC_PLAYER sequences and adjacent branch-as-jump patterns across platform renderers.

Relevant readers/writers found and known exclusions:
Apple render_viewport and render_single_tile each used BNE immediately after storing SC_PLAYER. Both are fixed. Commodore renderers load a nonzero player color after the zero-valued glyph before their BNE, so those branches remain valid and are excluded.

Initialization, reset and persistence points:
N/A — no initialized or persisted state changes.

Affected production sequence through the changed transition:
Town generation -> render_viewport -> player row/column match -> stage SC_PLAYER -> write tile -> finish remaining columns and rows -> status/message draw -> main loop. Dirty redraw follows render_single_tile -> player coordinate match -> stage SC_PLAYER -> write cell.

Contract decision or selected upstream oracle with source locations:
The captured Virtual ][ production trace; core/color.s SC_PLAYER = $00; platforms/apple2/dungeon_render_a2.s full and single-tile renderer control flow; rebuilt machine-code bytes at the two exits.

Intentional Moria8 deviations:
N/A — the Apple renderer now implements the same player-glyph override behavior as the Commodore renderers without depending on a color byte to set the zero flag.

Input/intermediate widths, signedness, carry, range and overflow policy:
N/A — the change replaces two relative conditional branches with absolute jumps and does not change values or arithmetic.

RNG reduction and bias, if applicable:
N/A — no RNG path changed.

Affected platforms, overlays, banks and owners:
Apple resident renderer only. The two one-byte expansions grow the resident image by two bytes while remaining inside its asserted owner. Commodore source and binaries are behaviorally unchanged.

Required production-path tests:
Cross-platform full build; Apple 296-assert link; Apple disk regeneration; rebuilt-byte inspection confirming JMP at both exits; Virtual ][ new-game-to-town runtime must finish the viewport, draw status/messages, and accept a command.

Known behavior explicitly out of scope:
Town screen geometry, ProDOS loading, character-selection key release, and unrelated renderer optimization.

Unresolved uncertainty and risk:
The captured trace establishes the failure and the corrected branch semantics directly. Runtime confirmation with the regenerated disk remains the only open gate.
```

### M3 LOOK overlay-dispatch repair record — 2026-07-21

```text
Problem and success criteria:
The LOOK command hung in town because Apple imported game_loop.s without PLAYER_LOOK_EXTERNAL. The emitted cmd_look therefore called do_look directly at $A400 without first loading the cold modal overlay; $A400 still belonged to the town overlay. Success is that LOOK dispatches through an always-resident trampoline, loads OVL_MODAL_MISC, calls do_look only after a successful load, and resynchronizes runtime state on both success and failure.

State being changed:
Apple overlay dispatch policy and control flow only. LOOK direction, visibility, descriptions, turn consumption, map state, and save representation are unchanged.

Search scope and terms:
CMD_LOOK, cmd_look, PLAYER_LOOK_EXTERNAL, tramp_do_look, do_look, PlayerMoveLookSegment, ModalMiscOverlay, overlay_load_no_kernal, tramp_sr_epilogue, and the emitted A2.PLAY call target.

Relevant readers/writers found and known exclusions:
game_loop.s owns cmd_look; player_move.s places do_look at the start of ModalMiscOverlay under the Apple segment macro; Apple main.s previously enabled PLAYER_LOOK_EXTERNAL only while importing player_move.s, not while importing game_loop.s. Commodore platforms already provide their own LOOK trampolines and are unchanged.

Initialization, reset and persistence points:
N/A — no initialized or persisted state changes.

Affected production sequence through the changed transition:
Main-loop LOOK dispatch -> play-resident tramp_do_look -> load OVL_MODAL_MISC into $A400 -> do_look -> runtime resync -> main loop. A failed load skips do_look and still resynchronizes before returning.

Contract decision or selected upstream oracle with source locations:
core/game_loop.s external LOOK policy; core/player_move.s overlay segment macros; platforms/commodore/c64/look_trampoline.s established dispatch semantics; platforms/apple2/main.s overlay ownership; emitted A2.PLAY bytes and symbols.

Intentional Moria8 deviations:
N/A — Apple now follows the existing external LOOK overlay contract.

Input/intermediate widths, signedness, carry, range and overflow policy:
Overlay ID is one byte. Carry from overlay_load selects load failure; do_look retains its carry-clear/free-action contract. No arithmetic changes.

RNG reduction and bias, if applicable:
N/A — no RNG path changed.

Affected platforms, overlays, banks and owners:
Apple A2.PLAY and OVL.MODAL only. The 13-byte trampoline ends A2.PLAY at $9FE3, below the asserted $A000 ceiling. Other platforms are unchanged.

Required production-path tests:
Apple build with 296 assertions; emitted-code inspection proving cmd_look JSR $9FD7 and trampoline load/call/resync sequence; Apple disk regeneration; Virtual ][ town LOOK must accept a direction, report the target, and return to the main loop.

Known behavior explicitly out of scope:
LOOK gameplay semantics, visibility calculations, modal contents, and unrelated overlays.

Unresolved uncertainty and risk:
The missing load is proven statically from the prior emitted JSR $A400 and ownership of that window. Runtime confirmation with the regenerated disk remains required.
```

### M3 post-MLI display-state repair record — 2026-07-21

```text
Problem and success criteria:
After descending from the working town, dungeon generation completed but the resulting screen contained alternating-column dollar signs and mangled text. The transition loads MONSTER.DB.1 through ProDOS before drawing the dungeon. The bundled ProDOS driver explicitly enables 80STORE/PAGE2 and later disables both, while the Apple renderer requires 80STORE to remain enabled so PAGE2 selects the aux/main halves of the 80-column text page. Success is that every runtime MLI epilogue restores that display invariant before any renderer resumes.

State being changed:
Apple II display soft-switch state after ProDOS MLI calls only. Dungeon topology, placement, monster records, combat, turn state, map bytes, and save representation are unchanged.

Search scope and terms:
a2_mli_begin, a2_mli_end, a2_platform_runtime_resync, 80STORE, PAGE2, $C000/$C001, $C054/$C055, screen_a2, dungeon_render_a2, tier_check_transition, MONSTER.DB.*, OVL.GEN, and the bundled tools/prodos/PRODOS bytes.

Relevant readers/writers found and known exclusions:
All storage_mli.s and save_stream.s runtime MLI paths converge on a2_mli_end. screen_a2.s and dungeon_render_a2.s toggle PAGE2 to choose the main or aux 80-column half and therefore require 80STORE on. The bundled ProDOS image contains STA $C001 and STA $C055 near file offset $0238, followed by STA $C054 and STA $C000 near $0258. RAMRD, RAMWRT, 80COL, ALTCHARSET, and INTC3ROM were inspected but are excluded from this repair because no evidence shows that this driver leaves them altered; restoring them would also exceed the resident boundary.

Initialization, reset and persistence points:
hal_platform_init establishes the initial display switches. a2_mli_end now calls the existing runtime-resync hook after restoring zero page and thunks, then restores the MLI result flags and accumulator. The hook enables 80STORE and selects PAGE2 off/main. No state is persisted.

Affected production sequence through the changed transition:
Town stairs -> tier_check_transition -> ProDOS OPEN/READ/CLOSE of MONSTER.DB.1 -> each MLI epilogue reasserts 80STORE and PAGE2 off -> dungeon generation/render -> PAGE2 selects the intended aux/main text half for each column pair. Overlay and save-file MLI paths receive the same required postcondition.

Contract decision or selected upstream oracle with source locations:
platforms/apple2/screen_a2.s defines the 80STORE/PAGE2 renderer contract; platforms/apple2/services.s establishes the same switches during initialization; platforms/apple2/storage_mli.s owns the common MLI epilogue; tools/prodos/PRODOS provides direct machine-code evidence that its driver disables 80STORE.

Intentional Moria8 deviations:
N/A — this restores the Apple renderer's established platform invariant and changes no gameplay or generation semantics.

Input/intermediate widths, signedness, carry, range and overflow policy:
a2_mli_end preserves A and the complete processor-status result from the MLI across resynchronization. The resync routine returns carry clear when called independently; no arithmetic or indexed range changes.

RNG reduction and bias, if applicable:
N/A — no RNG path changed.

Affected platforms, overlays, banks and owners:
Apple resident services and MLI epilogue only. The nine-byte growth leaves MORIA8.RES ending at $7BFD, inside the asserted $0A00-$7BFF owner and below A2.PLAY at $7C00. Commodore platforms are unchanged.

Required production-path tests:
Apple build with 296 assertions; emitted-byte inspection proving a2_mli_end calls $77B5 and that $77B5 contains STA $C001 / STA $C054 / CLC / RTS; disk regeneration; Virtual ][ cold-boot descent must render a coherent dungeon and return to command input. Shops, LOOK, combat, and later tier transitions should be exercised because their overlay/tier loads cross the same MLI boundary.

Known behavior explicitly out of scope:
Monster damage/status behavior, dungeon-generation balance, persistent runtime PAK conversion, ProDOS replacement, and emulator changes.

Unresolved uncertainty and risk:
The user screenshot strongly matches loss of 80STORE and the driver mutation is proven from the shipped ProDOS bytes, but no snapshot was captured at the corrupted dungeon screen. Runtime confirmation with the regenerated disk remains required before declaring the symptom closed. The resident region has two bytes of remaining headroom, so any later growth must move owned code rather than relax its boundary.
```

### M3 post-tier OVL.GEN cache repair record — 2026-07-21

```text
Problem and success criteria:
After the post-MLI display repair, descending generated the level but entered the Apple monitor at PC $1475. $1475 is zero-filled player_data, not an intentional BRK site. The captured Virtual ][ snapshot proves the active production chain was item_spawn_level -> pick_item_type -> overlay_load(OVL.GEN) -> ProDOS OPEN after MONSTER.DB.1 had overwritten the shared window. Success is that this OVL.GEN restoration is served from the boot aux cache and performs no runtime MLI OPEN.

State being changed:
Apple boot-container membership and aux-cache placement for immutable overlay payloads only. OVL.GEN bytes, dungeon stage order, RNG consumption, generated map state, monster/item placement, and overlay IDs are unchanged.

Search scope and terms:
The supplied 2026-07-21 224346 Virtual ][ snapshot; PC $1475; stack page; hal_storage_diag_phase/code; a2_open_ref; level_change_generate_current; item_spawn_level; pick_item_type; overlay_load; OVL_DUNGEON_GEN; tier_check_transition; MONSTER.DB.1; MORIA8.PAK; PAK_COUNT; cache_layout; fixed $1600 AUXMOVE; aux $5700-$BFFF.

Relevant readers/writers found and known exclusions:
The snapshot main-RAM base is file offset $0A1C, independently located by the emitted runtime-resync signature at CPU $77B5. Stack return values identify level_change_generate_current at $9482, item spawn at $4D76, pick_item_type at $516E, and overlay_load at $0AC4. Storage diagnostics are code $00, phase $20 (OPEN), with a2_open_ref already $01, proving ProDOS had not returned an error to product code. The working A2.PLAY bytes are intact. Persistent-Pak support for every remaining cold asset is excluded from this local repair.

Initialization, reset and persistence points:
MORIA8.SYSTEM now expects eight PAK entries and copies OVL.GEN from its staging buffer to aux $9900 during the existing single-open sequential boot pass. Runtime overlay lookup maps OVL_DUNGEON_GEN to that cache slot. The cache is immutable for the session and is not saved.

Affected production sequence through the changed transition:
Boot MORIA8.PAK single OPEN -> sequential OVL.GEN read -> aux $9900; town stairs -> cold MONSTER.DB.1 tier load into $A400 -> tier invalidates the overlay -> item_spawn_level -> pick_item_type requests OVL.GEN -> AUXMOVE $9900 to $A400 -> item selection and dungeon render continue without a second runtime ProDOS OPEN.

Contract decision or selected upstream oracle with source locations:
platforms/apple2/cache_layout.s owns aux cache placement; boot.s and Makefile own identical PAK order; overlay_storage.s owns overlay-ID-to-cache mapping; main.s link assertions own payload and copy bounds. The supplied production snapshot is the execution oracle for the failed transition. No gameplay oracle is needed because the payload and call order are byte-identical.

Intentional Moria8 deviations:
N/A — this changes only the Apple transport used to restore the same OVL.GEN payload.

Input/intermediate widths, signedness, carry, range and overflow policy:
PAK entry count changes from seven to eight; entry lengths remain unsigned 16-bit values. Page-rounded cache spans are TOWN $1500, UI $0E00, SPELL $1400, MODAL $0B00, GEN $1100, and ITEMS $1600, totaling exactly $6900 bytes from $5700 through $BFFF. ITEMS is last at $AA00 so the fixed $1600-byte runtime AUXMOVE ends exactly at the exclusive $C000 limit.

RNG reduction and bias, if applicable:
N/A — generation and item-selection RNG code and call order are unchanged.

Affected platforms, overlays, banks and owners:
Apple boot SYS, MORIA8.PAK, aux cache $5700-$BFFF, and OVL.GEN lookup only. Other platforms and main-memory layout are unchanged. The boot loader grows four bytes to end at $2133 and remains inside its asserted $0800-$09FF relocated owner.

Required production-path tests:
Apple link with 297 assertions; boot link with six assertions; regenerated PAK reporting eight entries and 61,503 bytes; disk image regeneration; emitted cache-table inspection; Virtual ][ cold boot -> town -> descend must pass item spawning, render the dungeon, and accept input without entering ProDOS OPEN for OVL.GEN.

Known behavior explicitly out of scope:
Persistent runtime PAK handling for tiers, saves, DEATH, HELP, STORAGE, TITLE, or START; replacing ProDOS; changing dungeon generation; and masking a returned storage error.

Unresolved uncertainty and risk:
The captured failing OVL.GEN OPEN is removed by construction, but Virtual ][ runtime confirmation remains required. Other cold runtime files still use independent ProDOS OPEN calls and may expose the same driver failure later; address those only from a captured failing production path or as an explicitly approved persistent-container change.
```

### M3 tier staging-base repair record — 2026-07-21

```text
Problem and success criteria:
With OVL.GEN boot-cached, descending remained at GENERATING. A first snapshot was incorrectly attributed to a bad MONSTER.DB.1 READ because its stale storage diagnostics reported phase READ and its $A400 window no longer held the tier payload. The supplied 2026-07-21 231128 Virtual ][ snapshot reproduces the same failure after a byte-exact boot cache removed that READ. Success is that tier activation reads the payload from the platform's actual BANKED_DATA_BASE and the tier-name copy terminates at that same staging region's end without overwriting the name pool or following memory.

State being changed:
The shared tier activation source address is expressed through the existing platform staging-base contract instead of a Commodore literal. Tier selection, tier bytes, record representation, creature values, generation stage order, RNG use, and map/monster placement semantics are unchanged.

Search scope and terms:
The 225806 and 231128 Virtual ][ snapshots; main and aux RAM blocks; stack page; $A000 name pool; $A400 window; saved ROM; current_tier; tier_load; load_tier_to_buffer; platform_copy_tier_names_to_pool; BANKED_DATA_BASE; TIER1_SIZE; and PLATFORM_TIER_NAME_POOL_BASE/END.

Relevant readers/writers found and known exclusions:
The 231128 snapshot proves the trial cache and new disk were active: aux $5000 matched all 830 MONSTER.DB.1 bytes, and A2.PLAY contained the cache helper. Its valid stack tail is tier_load return $3A1C -> tier_check_transition return $9479 -> level_change_generate_current return $93E6. tier_load nevertheless initialized zp_ptr0 to literal $E000 while Apple tier files and BANKED_DATA_BASE are $A400. After load_tier_to_buffer advanced that wrong source by 22 arrays x 24 records to $E210, platform_copy_tier_names_to_pool compared it with the correct $A73E end address. The comparison could not terminate normally. Snapshot main $A000-$BDEF is byte-identical to saved ROM $E210-$FFFF, proving the loop copied 7,664 ROM bytes through and beyond the 1,024-byte name pool; main $A400 therefore contained saved ROM $E610, explaining both snapshots without a failed READ. Tier file transport and generation logic are excluded.

Initialization, reset and persistence points:
N/A — no initialized or persisted state changes. The unsupported tier-1 boot-cache trial was removed; MONSTER.DB.1 returns to its existing on-demand loader.

Affected production sequence through the changed transition:
Town stairs -> level generation -> tier_check_transition -> tier_load_disk stages MONSTER.DB.1 at Apple BANKED_DATA_BASE $A400 -> tier_load initializes zp_ptr0 to $A400 -> load_tier_to_buffer copies 22 arrays -> source is $A610 -> name copy advances from $A610 to tier end $A73E -> rewrites 24 name pointers into the owned $A000-$A3FF pool -> tier transition returns -> generation overlay restore and monster/item placement continue.

Contract decision or selected upstream oracle with source locations:
platforms/apple2/memory.s defines BANKED_DATA_BASE=$A400 and the $A000-$A3FF name-pool owner; Commodore memory files define the same symbol as $E000. core/tier_manager.s already used BANKED_DATA_BASE to calculate the tier end and remap name offsets, making its literal $E000 source internally inconsistent. The supplied snapshot's stack and exact ROM-copy correspondence are the production failure oracle. No upstream gameplay oracle is required for this platform-address repair.

Intentional Moria8 deviations:
N/A — this restores the existing cross-platform tier representation and activation sequence.

Input/intermediate widths, signedness, carry, range and overflow policy:
Tier addresses are 16-bit. BANKED_DATA_BASE is asserted page-aligned because the existing end calculation adds TIERn_SIZE high/low bytes to a zero-low-byte base. For tier 1, 22 arrays x 24 bytes advance $A400 to $A610; TIER1_SIZE 830 ends at exclusive $A73E; the 302-byte name block fits the 1,024-byte $A000-$A3FF pool. No arithmetic, carry, truncation, or saturation policy changes.

RNG reduction and bias, if applicable:
N/A — no RNG code, state, reduction, or call order changes.

Affected platforms, overlays, banks and owners:
Shared tier_manager source. Apple emitted activation changes from immediate $E000 to $A400 inside its resident owner. C64, C128, and Plus/4 BANKED_DATA_BASE remains $E000, so their emitted address semantics are unchanged. The removed cache trial restores Apple resident end $7BFD, A2.PLAY end $9FE5, eight-entry PAK, and the unused aux $5000-$56FF gap.

Required production-path tests:
Apple link with 298 assertions including the staging-base alignment guard; emitted bytes at tier activation must be A9 00 / A9 A4; boot link with six assertions; regenerated eight-entry PAK and disk image; full C64/C128/Plus4/Apple build; Virtual ][ cold boot -> town -> descend must leave GENERATING, render a coherent dungeon, and accept input.

Known behavior explicitly out of scope:
Tier transport redesign, persistent runtime PAK handling, save files, cold overlays, ProDOS replacement, generation topology/RNG, monster values/AI, and emulator changes.

Unresolved uncertainty and risk:
The overwrite and its address mismatch are directly proven, and the corrected name-copy bounds close mathematically. Virtual ][ confirmation remains required. Later tier transitions still use runtime ProDOS loads and are separate transport-risk coverage, but no captured evidence currently shows those reads return incorrect bytes.
```

### M3 new-game invulnerability initialization repair record — 2026-07-21

```text
Problem and success criteria:
A monster reported a successful hit but the new character appeared to take no damage and the HP status did not change. The captured Virtual ][ snapshot proves eff_invuln_timer ($006F) was $FF after new-game initialization. mon_atk_apply_damage deliberately suppresses all HP subtraction while that timer is nonzero, and turn processing would require 255 turns to expire the accidental value. Success is that every new game explicitly initializes the timer to zero before character creation and ordinary successful monster attacks can mutate HP immediately.

State being changed:
New-game initialization of the existing transient invulnerability timer only. The Holy Word duration, damage formula, hit roll, HP representation, status cache, and save format are unchanged.

Search scope and terms:
eff_invuln_timer, zp_snd_spare, $006F, game_new_start, clear_effects, mon_atk_apply_damage, turn_tick_effects, status_mark_dirty, status_draw, Holy Word, hal_sound_init, and all production/test writers of the timer.

Relevant readers/writers found and known exclusions:
mon_atk_apply_damage and monster spell damage read the timer as an immunity gate; turn_tick_effects decrements it; Holy Word sets it to three. game_new_start cleared only ZP $50-$5F and eff_fear_timer, while no platform hal_sound_init writes zp_snd_spare/$6F. The existing hit/damage and status-dirty paths are correct and are excluded from modification.

Initialization, reset and persistence points:
game_new_start now stores zero to eff_invuln_timer alongside the other transient effect clears. Holy Word remains the sole production grant found. The timer remains transient and is not added to save data.

Affected production sequence through the changed transition:
New game -> clear transient effects including $006F -> character creation -> town/dungeon turns -> monster hit -> mon_atk_apply_damage sees zero and subtracts zp_combat_dmg -> turn_post_action marks status dirty -> status_draw detects the HP cache change and redraws row 23.

Contract decision or selected upstream oracle with source locations:
core/game_loop.s owns new-game transient-state initialization; core/monster_attack.s owns the invulnerability gate and HP subtraction; core/turn.s owns duration decrement and status dirtiness; core/ui_status.s owns HP-cache comparison. The supplied Virtual ][ snapshot provides the failing production-state oracle: its main-RAM block starts at file offset $0A1C, making CPU $006F file offset $0A8B, whose value is $FF.

Intentional Moria8 deviations:
N/A — a fresh character no longer inherits undefined machine zero-page contents as gameplay invulnerability.

Input/intermediate widths, signedness, carry, range and overflow policy:
The timer is an unsigned byte. Zero means inactive; Holy Word writes three; turn processing decrements only nonzero values. No damage arithmetic or carry behavior changes.

RNG reduction and bias, if applicable:
N/A — no RNG path changed.

Affected platforms, overlays, banks and owners:
Shared game_new_start behavior on C64, C128, Plus/4, and Apple II. On Apple the two-byte STA grows A2.PLAY to end at $9FE5, below its asserted $A000 ceiling. Resident memory is unchanged by this repair.

Required production-path tests:
C128 main_loop128 production test seeds eff_invuln_timer to $FF, calls game_new_start, and requires zero afterward; full cross-platform build; Apple build with 296 assertions and disk regeneration; Virtual ][ cold-boot combat must reduce displayed HP after an ordinary reported hit. Existing monster-attack tests continue to cover deliberate Holy Word immunity.

Known behavior explicitly out of scope:
Monster attack balance, armor reduction, status layout, Holy Word duration, persistence of active effects across saves, and the independent post-MLI display corruption.

Unresolved uncertainty and risk:
The omitted initialization and failing $FF runtime value are directly proven, and the production initializer regression passes. A fresh Virtual ][ run remains required to confirm both HP memory and row-23 presentation on Apple hardware emulation.
```

### M3 death-overlay high-score counter ownership repair record — 2026-07-21

```text
Problem and success criteria:
The death screen rendered, but dismissal did not return to the title menu. The supplied 2026-07-21 233901 Virtual ][ snapshot shows a successfully loaded OVL.DEATH whose byte at CPU $A402 differs from the built payload: the LDX #0 opcode in game_restart_overlay changed from $A2 to $00 (BRK). Success is that high-score load/save cannot mutate death-overlay code and dismissal executes the intact restart entry.

State being changed:
Apple ownership of the two-byte high-score transfer counter only. Score calculation, table format, file format, death presentation, input policy, and restart semantics are unchanged.

Search scope and terms:
The supplied snapshot main RAM; OVL.DEATH byte comparison; game_restart_overlay; hiscore_load; hiscore_save; save_count_lo/hi; all symbols at $A400-$A40F; overlay_load; current_overlay; and the death-to-title production sequence.

Relevant readers/writers found and known exclusions:
core/score_io.s used save_count_lo/hi for both high-score reads and writes. On Apple those symbols are owned by OVL.STORAGE at $A402/$A403, while score_io.s executes from OVL.DEATH and game_restart_overlay owns $A400 onward. The snapshot's only unexpected early-overlay difference is $A402=$00, exactly the final low count written by high-score I/O. The cold death load, ProDOS status, modal input, score fields, and expected mutable death-overlay data were inspected and excluded.

Initialization, reset and persistence points:
The new death-local counter is initialized whenever a non-empty high-score transfer begins and is consumed to zero by that transfer. It is overlay scratch, is reloaded with OVL.DEATH, and is not persisted.

Affected production sequence through the changed transition:
Player death -> load OVL.DEATH -> calculate score -> load/insert/save high scores using death-local counter -> render death screen -> read dismissal key -> game_over_prompt observes OVL.DEATH already current -> execute intact game_restart_overlay -> title menu.

Contract decision or selected upstream oracle with source locations:
platforms/apple2/main.s defines OVL.DEATH and OVL.STORAGE as mutually exclusive occupants of $A400-$B9FF; core/score_io.s owns the high-score transfer loop; platforms/shared/save.s owns save_count_lo/hi; the supplied snapshot and rebuilt overlay bytes provide the production failure oracle. The fix restores overlay-local mutable ownership and requires no gameplay oracle.

Intentional Moria8 deviations:
N/A — high-score contents, ordering, persistence, death flow, and player-facing text are unchanged.

Input/intermediate widths, signedness, carry, range and overflow policy:
The transfer count remains unsigned 16-bit and is still computed as entry count (0-10) times 23 bytes, for a maximum of 230. Decrement and termination behavior are byte-for-byte unchanged apart from the counter address.

RNG reduction and bias, if applicable:
N/A — no RNG code or call order changes.

Affected platforms, overlays, banks and owners:
Apple OVL.DEATH gains two owned bytes at $A43C/$A43D and grows to exclusive end $AB9E. OVL.STORAGE retains save_count_lo/hi at $A402/$A403. Link assertions require both death ownership and non-aliasing. C64, C128, and Plus/4 keep aliases to their resident save counters, preserving their emitted sizes and behavior.

Required production-path tests:
Full C64/C128/Plus4/Apple build; Apple 300-assert link including the two new ownership guards; emitted OVL.DEATH must retain A9 00 A2 00 at $A400 after a modeled high-score counter transfer; disk regeneration; Virtual ][ death-screen dismissal must return to a responsive title menu. The Turn/Render verification matrix is N/A because no redraw state, visibility, renderer, or input routine changes.

Known behavior explicitly out of scope:
High-score policy or layout, save-media prompting, ProDOS transport redesign, death-screen artwork/text, and unrelated overlay aliases.

Unresolved uncertainty and risk:
The corrupt opcode and its exact writer alias are directly proven. Static ownership checks close the alias by construction; Virtual ][ confirmation with the regenerated disk remains the production runtime gate.
```

### M3 ego-trampoline ownership repair record — 2026-07-22

```text
Problem and success criteria:
The emitted OVL.TITLE extended 74 bytes past its declared ovl_title_end because four ego-item trampolines inherited the TitleOverlay segment. Each trampoline loads OVL.ITEMS, so executing one from the overlay window could overwrite its own remaining instructions. Success is that OVL.TITLE ends exactly at ovl_title_end and every ego trampoline executes from persistent resident or play memory.

State being changed:
Apple linker ownership and placement of the existing ego dispatch wrappers only. Ego selection, bonuses, damage, names, RNG, and item records are unchanged.

Search scope and terms:
ovl.title emitted extent; ovl_title_end; tramp_roll_ego_type; tramp_ego_apply_damage; tramp_ego_get_ac_bonus; tramp_ego_append_suffix; OVL_ITEMS; A2PlaySlot; Default; ui_help_clear; combat_append_str; and every core caller of the four trampolines.

Relevant readers/writers found and known exclusions:
The static memory checker measured OVL.TITLE at exclusive end $A5C8 while ovl_title_end was $A57E. The exact $4A-byte tail was the four trampolines. Their callers are wizard/item generation, combat damage, equipment recalculation, and item-description suffix construction. Title behavior, item overlay implementations, and non-Apple trampolines are excluded.

Initialization, reset and persistence points:
N/A — no state is initialized, reset, saved, or restored. The Apple help source pointer remains initialized by tramp_ui_help_display immediately after it loads OVL.HELP and before ui_help_display reads it.

Affected production sequence through the changed transition:
Gameplay caller -> persistent ego trampoline -> load OVL.ITEMS into $A400 -> call ego implementation -> return to persistent code. Suffix construction then tail-calls the existing bounded combat_append_str routine from the persistent play payload.

Contract decision or selected upstream oracle with source locations:
docs/APPLE2_MEMORY_POLICY.md and platforms/apple2/main.s assign $A400-$B9FF to mutually exclusive overlays, $0A00-$7BFF to resident code, and $7C00-$9FFF to the persistent play payload. Emitted PRG extents and linked end symbols are the ownership oracle; no gameplay oracle is needed because the dispatched implementations and inputs are unchanged.

Intentional Moria8 deviations:
N/A — this repairs Apple memory ownership without changing gameplay semantics or player-visible text.

Input/intermediate widths, signedness, carry, range and overflow policy:
The one-byte ego type and overlay-load carry result are unchanged. Suffix copying now uses combat_append_str, whose existing bound reserves the final combat-message byte for a null terminator; this matches and strengthens the former local loop's intended bound.

RNG reduction and bias, if applicable:
N/A — no RNG code, reduction, state, or call order changes.

Affected platforms, overlays, banks and owners:
Apple OVL.TITLE now ends at $A57E exactly. Three 11-byte call wrappers live in resident RAM, whose exclusive end is $7BF0. The 24-byte suffix wrapper lives in A2.PLAY, whose exclusive end is $9FFE. Apple omits a 47-byte resident fallback help table that cannot be read on its production path; Commodore builds retain it. New link assertions enforce the trampoline owners and both region ceilings.

Required production-path tests:
`make testapple2-memory-contract-selftest`; `make testapple2-memory-contract`, including exact emitted/linker ends and 302 assembler assertions; full `make build` for cross-platform link parity. Runtime ego generation, ego combat, equipment recalculation, and ego item description remain desirable manual Virtual ][ coverage because the current Apple harness has no such scenario.

Known behavior explicitly out of scope:
Ego balance, item-generation probabilities, help content, persistent runtime PAK conversion, and emulator behavior.

Unresolved uncertainty and risk:
Static ownership and extent checks close the overwrite by construction. The suffix wrapper reuses an already production-tested bounded appender, but the four Apple ego paths do not yet have automated runtime scenarios.
```

- Per-module size attribution: done at M0 (`docs/APPLE2_MEMORY_POLICY.md`,
  measured at `f7d322d`).
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
