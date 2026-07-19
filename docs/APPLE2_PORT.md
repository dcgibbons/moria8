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
| `$0400-$07FF` | 1,024 | 80-col text page, main half (odd columns); screen holes (`$x78-$x7F`) never touched |
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
- Perf bounds: +~25 cycles per aux byte; full 78x19 redraw ~45 ms at
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
| `main.s` | Linker script + entry: segmentdefs for resident payloads (C128-style splits per M0 table), all overlay segments (`outPrg`, start `$A200`, window max bounds), play slot + slot-hosted modal segments, `.const C128=false`/`PLUS4=false`, complete import cascade (clone c64 `main.s` order), title/menu flow, boundary `.assert`s |
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
bidirectional protocol.

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
