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

Marker semantics: GET_FILE_INFO on `MORIA8.ID`. Placement: OVL.STORAGE
class, window-hosted at `$A400` (supersedes the M0 `$7C00` sketch).

Superseded 2026-07-25 (maintainer direction, Disk Setup parity task):
"save volume = game volume; the two-drive swap UX degrades to
always-present probes — final behavior." The port now ships the full
Commodore-parity guided Disk Setup; see the 2026-07-25 record below.

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

### MAME ROM set pitfalls (verified with MAME 0.288)

Older Apple II romsets are missing two ROMs that this MAME version
requires, and the failure modes are silent:

- `341-0028-a.rom` — the Disk II controller P6 LSS state-machine PROM
  (MAME `d2fdc`/`wozfdc` device). Missing or zeroed: the data latch never
  fills, so the boot ROM spins forever at `$C65E` waiting for the
  `D5 AA 96` prologue. This is the "corrupt ROMs" boot hang.
- `341-0132-d.e12` — the AY3600 keyboard decode ROM. Missing or zeroed:
  every keypress decodes to `$00`. The game boots but ignores all input.
  The table maps matrix position to ASCII per caps/shift/ctrl and layout;
  MAME's X1 matrix wires the row as Q,W,E,R,Y,T,U,I,O (T/Y order differs
  from the keycap row), which a synthesized table must match. All keys
  the game uses are verified against the synthesized table; a real dump
  (CRC `c506efb9`) should replace it when available.
- `sc01a.bin` — Votrax speech ROM for the default sl4 Mockingboard.
  Inert for this game; any content works.
- Input scenarios post keys through the `:X0`-`:X8` ioport matrix fields
  (`field:set_value`), not `natkeyboard:post()`, and must hold keys for
  ~30 ms emulated to avoid the IIe 15 Hz typematic repeat.

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

### M3 bash level-up overlay-return repair record — 2026-07-22

```text
Problem and success criteria:
Killing a monster with Bash at a level threshold printed executable bytes as combat text, repeatedly raised the player to level 40, inflated HP/XP, and exhausted the hardware stack. Success is that Bash may trigger exactly the normal finite level-up sequence, then resumes its ITEMS-overlay continuation with OVL.ITEMS physically resident and accepts subsequent commands without corrupting combat text or player state.

State being changed:
Apple overlay ownership at the Bash-to-resident-level-up return boundary only. Monster records, damage, XP awards, level thresholds, HP/mana formulas, spell learning, messages, turn consumption, and save representation are unchanged.

Search scope and terms:
The supplied 2026-07-22 001724 Virtual ][ snapshot; main/aux RAM and stack page; current_overlay; OVL.ITEMS and OVL.SPELL cache slots; bash_monster; combat_award_xp; combat_check_levelup; combat_apply_levelup; tramp_magic_recalc_mana; tramp_magic_check_new_spells; magic_check_new_spells; msg_build_action; combat_msg_buf; and all production combat_check_levelup callers.

Relevant readers/writers found and known exclusions:
The snapshot's aux cache at $AA00 matches the built ITEMS payload byte-for-byte and its SPELL cache at $7A00 matches the built SPELL payload byte-for-byte, excluding disk/cache corruption. Stack page $0140-$01F8 repeats return frames $B493 (Bash after combat_check_levelup), $8CBF (combat_check_levelup after combat_apply_levelup), $8D4C (combat_apply_levelup after the SPELL helper), and $B4B6 (Bash after bash_off_balance), proving recursive cross-overlay execution. combat_msg_buf contains bytes copied from live A2.PLAY code and the saved action pointer is $8601 rather than a legal combat verb, explaining the rendered garbage. Normal melee calls combat_check_levelup from resident A2.PLAY; spell-effect kills call it from OVL.SPELL; Bash is the only found caller whose continuation is in OVL.ITEMS while level-up helpers replace that window with OVL.SPELL.

Initialization, reset and persistence points:
N/A — no new persistent or initialized gameplay state. The repair reloads the immutable boot-cached ITEMS payload before returning to the existing Bash continuation; current_overlay is updated by the existing broker.

Affected production sequence through the changed transition:
Bash monster kill in OVL.ITEMS -> always-resident wrapper -> combat_check_levelup/combat_apply_levelup in A2.PLAY -> level-up magic helpers load and execute OVL.SPELL -> resident wrapper reloads OVL.ITEMS from aux cache -> return to bash_monster after its level check -> kill bookkeeping/off-balance -> normal turn completion.

Contract decision or selected upstream oracle with source locations:
docs/APPLE2_MEMORY_POLICY.md assigns $A400-$B9FF to one mutually exclusive overlay and $7C00-$9FFF to persistent A2.PLAY. platforms/apple2/main.s owns resident overlay trampolines; core/bash.s owns the Bash continuation. The snapshot stack is the production failure oracle. Existing combat_check_levelup behavior remains the semantic oracle because no gameplay rule changes.

Intentional Moria8 deviations:
N/A — this restores the existing Bash, XP, level-up, spell-learning, and off-balance sequence.

Input/intermediate widths, signedness, carry, range and overflow policy:
Overlay IDs remain unsigned bytes. The wrapper ignores combat_check_levelup's incidental register/flag results, requests OVL.ITEMS, and may return only after carry-clear load success; a failed reload cannot safely return into the overwritten window and therefore uses the existing fatal BRK convention for impossible cached-continuation failures. XP, HP, mana, level, damage, and RNG arithmetic are unchanged.

RNG reduction and bias, if applicable:
N/A — no RNG code, inputs, call count, or reduction changes.

Affected platforms, overlays, banks and owners:
Apple only: one 12-byte always-resident wrapper and the Apple conditional Bash call site. OVL.ITEMS and OVL.SPELL layouts and cache payloads are unchanged except for any address shift caused by the three-byte call-target substitution. C64, C128, and Plus/4 retain their direct combat_check_levelup call.

Required production-path tests:
Apple link and memory-contract checker; regenerated Apple disk; emitted-call inspection proving Bash targets the resident wrapper and that the wrapper reloads OVL.ITEMS before RTS; full cross-platform build because core/bash.s is shared. The active runtime gate is Virtual ][ cold boot -> dungeon -> Bash-kill a monster at the next XP threshold: one finite level-up, sane HP/XP, readable messages, off-balance at most once, and responsive subsequent input. Monster State conditional rows are N/A because no record, attack, visibility, sleep, or targeting transition changes. Turn/Render conditional rows are N/A because command consumption, redraw events, visibility, and rendering are unchanged.

Known behavior explicitly out of scope:
Combat balance, level thresholds, bash hit/damage/off-balance formulas, monster AI and attacks, message wording, generic nested-overlay refactoring, cold-file transport, and emulator behavior.

Unresolved uncertainty and risk:
The invalid overlay return and its downstream recursion are directly proven. Static ownership and emitted-call checks can prove the return boundary, but the repository has no automated Apple gameplay harness for a threshold Bash kill; the supplied Virtual ][ reproduction remains the production runtime confirmation.
```

### M3 chargen class-list renderer scratch repair record — 2026-07-22

```text
Problem and success criteria:
The Apple class-selection page intermittently showed only overlapping entries such as `a) Warrior`, `f) Rogue`, and `i) Mage`, with a malformed `Choose (a-i)` range. Success is that every allowed class appears once on consecutive rows, letters are consecutive from `a`, the prompt ends at the actual allowed-class count, and each accepted letter maps to the displayed class.

State being changed:
Apple screen-service scratch ownership only. Character class restrictions, class ordering, selection mapping, player data, text, and input semantics are unchanged.

Search scope and terms:
create_select_class; zp_temp2/3/4; create_class_map; race_class_flags; hal_screen_put_string; screen_put_string; screen_put_char_at; a2_write_cell; a2_zp_scratch; every Apple writer of zp_temp4; and the supplied broken-page screenshot.

Relevant readers/writers found and known exclusions:
create_select_class owns zp_temp4 as both the consecutive display-row counter and valid-class count across each class-name print. Apple screen_put_string also stored its per-character index in zp_temp4, leaving the class name length there before the caller incremented it. `Warrior` therefore changed the next display position from 1 to 8; later names repeatedly changed the count and overwrote rows, exactly accounting for the screenshot. The shared HAL screen contract allows A/X/Y clobbers but does not grant screen services ownership of core zero-page scratch. Apple screen_put_char_at had the same unnecessary zp_temp4 use. Race filtering tables, class names, aux/main text interleave, keyboard input, and overlay bytes are excluded.

Initialization, reset and persistence points:
N/A — no gameplay state is initialized, reset, or persisted. The existing platform-owned a2_zp_scratch byte is transient and requires no initialization.

Affected production sequence through the changed transition:
Character creation -> race selection -> stat roll -> class selection -> for each allowed class, preserve the caller's core scratch while the Apple renderer indexes and writes the name -> increment the unchanged display count -> build the selection map and prompt -> accept one valid key.

Contract decision or selected upstream oracle with source locations:
platforms/commodore/hal/hal_screen.s defines screen services as clobbering A/X/Y, not shared core scratch; platforms/apple2/memory.s assigns a2_zp_scratch to the platform; core/player_create.s owns zp_temp4 for the class-list loop. The screenshot and the deterministic string-length progression are the failure oracle. Existing race_class_flags and class_name_ptrs define the intended list and mapping.

Intentional Moria8 deviations:
N/A — this restores the existing class-selection presentation and mapping.

Input/intermediate widths, signedness, carry, range and overflow policy:
The renderer index, class index, and valid-class count remain unsigned bytes. Class index is bounded by CLASS_COUNT=6, valid count by 1..6, and an 80-column row bounds the renderer index. Replacing core zp_temp4 with platform a2_zp_scratch changes no arithmetic, carry, truncation, or bounds.

RNG reduction and bias, if applicable:
N/A — stat generation and all RNG code/call order are unchanged.

Affected platforms, overlays, banks and owners:
Apple only. Two renderer scratch references in screen_put_string and two in screen_put_char_at move from core zp_temp4 ($0C) to platform a2_zp_scratch ($A8), byte-for-byte in instruction size. Resident, play, overlay, and aux payload extents are unchanged. Commodore renderers and emitted binaries are unchanged.

Required production-path tests:
Full cross-platform build; Apple memory-contract checker; regenerated Apple disk; emitted-byte inspection showing Apple screen_put_string and screen_put_char_at use $A8 and no longer reference $0C. The active runtime gate is Virtual ][ new character creation with at least Human (six entries `a`-`f`) and one restricted race: consecutive rows/letters, correct prompt bound, selectable first and last entries. Turn/Render gameplay matrix rows are N/A because this page runs before gameplay and changes no dirty event, visibility, repeat command, or gameplay renderer transition.

Known behavior explicitly out of scope:
Race/class balance and restrictions, stat rolling, character-creation ordering, player-visible wording, Apple font glyphs, generic scratch auditing outside the two screen services, and automated Apple chargen-harness expansion.

Unresolved uncertainty and risk:
The shared-byte collision and screenshot are exact. Static emitted-byte inspection closes the scratch alias; the current Apple harness has no chargen-page scenario, so Virtual ][ confirmation remains required.
```

### M3 help-line renderer ownership repair record — 2026-07-22

```text
Problem and success criteria:
Online help renders corrupt text on Apple II. Success is that both help pages render readable text, inline emphasis changes do not alter characters, navigation works, and dismissal restores responsive gameplay.

State being changed:
Apple help-line presentation routing only. Help text, page structure, navigation, input, gameplay state, and modal lifecycle are unchanged.

Search scope and terms:
tramp_ui_help_display; ui_help_display; help_draw_line; HAL_SCREEN_HELP_LINE_USES_API; hal_screen_help_line_uses_api; zp_screen; zp_color; screen_put_char; Apple 80-column aux/main interleave; and every platform policy definition of the help-line route.

Relevant readers/writers found and known exclusions:
core/ui_help.s has two implementations: the HAL-character API path and a direct linear screen/color-RAM path. Apple selected the direct path even though each 80-column row is split between aux and main RAM, row addresses are non-linear, and there is no color RAM. That path writes sequential main RAM and a false color pointer, accounting for corrupt output and risking screen-hole writes. C128 already selects the HAL API for its non-linear VDC display. Help data and the surrounding modal flow are excluded.

Initialization, reset and persistence points:
N/A — no state is added or persisted. Existing cursor and logical-color setup remains authoritative.

Affected production sequence through the changed transition:
`?` command -> resident help trampoline -> OVL.HELP -> help page setup -> each decoded line routes every ordinary character through hal_screen_put_char -> Apple character mapping and aux/main cell write -> page navigation/dismissal -> gameplay restore.

Contract decision or selected upstream oracle with source locations:
platforms/apple2/screen_a2.s owns the Apple text layout and exposes hal_screen_put_char as the only character writer that maps logical columns to the correct aux/main half. core/ui_help.s explicitly provides HAL_SCREEN_HELP_LINE_USES_API for non-linear displays. Existing C128 policy is the structural oracle; existing help data and navigation are the semantic oracle.

Intentional Moria8 deviations:
N/A — this restores the shared help content on the Apple display.

Input/intermediate widths, signedness, carry, range and overflow policy:
Rows, columns, characters, and inline markers remain unsigned bytes. The help content remains bounded by the existing 80-column layout. No arithmetic, carry contract, truncation, or range changes.

RNG reduction and bias, if applicable:
N/A — no RNG use.

Affected platforms, overlays, banks and owners:
Apple only: define HAL_SCREEN_HELP_LINE_USES_API in the resident screen backend so OVL.HELP emits API calls instead of direct memory writes. Commodore policies and help data are unchanged. The overlay remains in $A400-$B9FF and must continue to satisfy its fit assert.

Required production-path tests:
Full build; Apple memory-contract checker and regenerated disk; emitted help_draw_line inspection proving ordinary characters call hal_screen_put_char and do not write through zp_color. Runtime gate: Virtual ][ town and dungeon `?`, both pages readable, navigation and ESC dismissal responsive, gameplay correctly restored. Turn/Render conditional rows are N/A because gameplay dirty events, visibility, and turn consumption are unchanged; this changes only modal presentation routing.

Known behavior explicitly out of scope:
Help wording, colors on monochrome Apple text, general modal redesign, keyboard mapping, and unrelated screen services.

Unresolved uncertainty and risk:
The invalid writer selection is proven statically. The current automated Apple harness has no help scenario, so exact rendered content and modal return still require Virtual ][ coverage.
```

### M3 spell-list overlay-return repair record — 2026-07-22

```text
Problem and success criteria:
Magic/prayer selection cannot safely return after the player opens the `?` spell list, and mage study has the same invalid return after its local spell list. Success is that an eligible character can select a matching book, open the cast/pray/study list, select or cancel, restore the gameplay view, execute the existing result when selected, and accept subsequent commands without a hang or corruption.

State being changed:
Apple physical overlay ownership across spell-list modal dismissal only. Eligibility, books, learned masks, spell choice, mana, failure/effect behavior, messages, turn consumption, and gameplay redraw semantics are unchanged.

Search scope and terms:
player_cast_spell; player_pray; item_gain_spell; pm_prompt_visible_spell_choice; tramp_spell_list_display; spell_list_display; ui_view_restore_modal_overlay; tier_restore_after_overlay; current_overlay; OVL.SPELL; overlay window; every post-spell-list return path; and the existing Bash overlay-return repair.

Relevant readers/writers found and known exclusions:
pm_prompt_visible_spell_choice and item_gain_spell continuations execute in OVL.SPELL at $A400. The cast/pray `?` path and mage study list both call ui_view_restore_modal_overlay directly. Apple modal restore calls tier_restore_after_overlay, which repopulates the same $A400 window with monster tier data before RTS; the next instruction in either caller is therefore overwritten. Direct cast/pray spell-letter selection does not run this modal restore and is excluded. The earlier book selector explicitly restores OVL.SPELL and is also excluded.

Initialization, reset and persistence points:
N/A — no new state. The existing broker updates current_overlay and tier ownership.

Affected production sequence through the changed transition:
cast/pray in OVL.SPELL -> select book -> press `?` -> draw spell list -> capture selection key -> resident modal-restore wrapper -> reset message state, restore tier, redraw gameplay/status -> reload boot-cached OVL.SPELL -> return to the saved spell continuation -> select/cancel normally. Mage study follows the same wrapper after its local list for both selection and cancel.

Contract decision or selected upstream oracle with source locations:
docs/APPLE2_MEMORY_POLICY.md gives the tier and all code overlays mutually exclusive ownership of $A400-$BAFF. core/ui_restore.s intentionally restores the tier before redraw. platforms/apple2/main.s owns resident cross-overlay trampolines. The established Bash repair is the structural oracle; existing spell logic is the semantic oracle.

Intentional Moria8 deviations:
N/A — this restores existing spell-list behavior.

Input/intermediate widths, signedness, carry, range and overflow policy:
Overlay IDs and selection keys remain unsigned bytes. The wrapper preserves no result from ui_view_restore_modal_overlay because its contract preserves nothing; it reloads OVL.SPELL or executes the existing fatal BRK convention rather than return into overwritten code. Spell arithmetic and carry contracts are unchanged.

RNG reduction and bias, if applicable:
N/A — modal presentation and overlay restoration use no RNG.

Affected platforms, overlays, banks and owners:
Apple only: the shared player_magic call site conditionally targets a resident Apple wrapper. That wrapper and the Bash wrapper share one resident checked overlay-reload epilogue. OVL.SPELL remains cached and window-owned. Commodore call sites remain direct.

Required production-path tests:
Full cross-platform build; Apple memory-contract checker and regenerated disk; emitted-call inspection proving the Apple cast/pray and study list exits call the resident wrapper and reload OVL.SPELL after tier restore. Runtime gate: mage magic and priest prayer using `?`, mage study selection and cancel, correct gameplay/status redraw, and responsive next command. Turn/Render rows: the existing modal-dismiss dirty/visibility/status sequence is unchanged; only physical code ownership is repaired after it. Monster rows are N/A because tier bytes are restored through the existing authoritative path and no monster state or targeting semantics change.

Known behavior explicitly out of scope:
Direct spell-letter selection, spell effects/balance, learning rules and available-spell calculation, command-key case, help content, item wear, and generic overlay redesign.

Unresolved uncertainty and risk:
The return address and overwrite are proven from linked ownership and the unconditional tier restore. Runtime mage/priest coverage remains manual because the Apple harness has no spell scenario.
```

### M3 wear inventory-overlay return repair record — 2026-07-22

```text
Problem and success criteria:
Wear cannot safely return when the player presses `?` at the wearable-item prompt. Success is that `W`, `?`, and a listed item equips exactly that item; ESC cancels; the gameplay view/status return correctly; and subsequent input remains responsive. Direct prompt-letter selection must remain unchanged.

State being changed:
Apple inference of the physical return overlay for the existing selectable inventory modal. Inventory/equipment data, wearable filtering, swaps, combat recalculation, messages, turn consumption, and item letters are unchanged.

Search scope and terms:
tramp_item_wear; item_wear; piw_select_filtered_inv; show_inv_and_select; tramp_ui_inv_select_display; piw_return_overlay; current_overlay; stack return-address checks; OVL.ITEMS; OVL.SPELL; OVL.HELP; and every caller that supplies an explicit return-overlay hint.

Relevant readers/writers found and known exclusions:
The wear continuation is in OVL.ITEMS. show_inv_and_select correctly detects from the hardware stack that a no-hint caller is inside the overlay window, but after tramp_ui_inv_select_display it reads current_overlay to decide which owner to restore. current_overlay is then OVL.HELP, so neither ITEMS nor SPELL is selected; modal restore loads the tier and RTS targets overwritten ITEMS bytes. Apple spell callers already set piw_return_overlay explicitly before entering the item selector. Therefore an Apple no-hint overlay caller at this point is ITEMS; direct resident callers and explicit SPELL callers are excluded.

Initialization, reset and persistence points:
No new state. piw_return_overlay continues to be cleared by the existing restore path before reload.

Affected production sequence through the changed transition:
W -> resident item trampoline -> OVL.ITEMS item_wear -> wearable prompt -> `?` -> OVL.HELP inventory list -> capture item key -> stack detects an overlay continuation -> Apple assigns the no-hint owner OVL.ITEMS -> modal restore/tier redraw -> reload boot-cached OVL.ITEMS -> validate chosen item -> equip/recalculate/message -> normal turn completion.

Contract decision or selected upstream oracle with source locations:
core/player_items.s documents piw_return_overlay as the product return owner and already treats explicit hints as authoritative. platforms/apple2/main.s routes all no-hint wear/takeoff command bodies through OVL.ITEMS and supplies explicit hints for SPELL item selection. docs/APPLE2_MEMORY_POLICY.md defines exclusive window ownership. Existing direct-letter wear semantics remain the oracle.

Intentional Moria8 deviations:
N/A — this restores the shared selectable-inventory behavior.

Input/intermediate widths, signedness, carry, range and overflow policy:
Overlay IDs, item IDs, slots, and item keys remain unsigned bytes with existing bounds. No equipment arithmetic, carry result, or filter range changes.

RNG reduction and bias, if applicable:
N/A — wear selection and equipment recalculation use no RNG.

Affected platforms, overlays, banks and owners:
Apple behavior only, expressed inside the shared product-overlay branch. The Apple no-hint owner becomes OVL.ITEMS; existing C64/C128/Plus4 inference remains unchanged. The change reduces Apple resident code and changes no overlay payload data.

Required production-path tests:
Full cross-platform build; Apple memory-contract checker and regenerated disk; emitted inspection showing the Apple no-hint stack path records OVL.ITEMS and reloads it after modal restore. Runtime gate: W direct-letter success, W `?` selection success, ESC cancel, swap with occupied equipment if available, status/equipment view update, and responsive next command. Turn/Render rows: successful wear still consumes one turn and requests the existing full redraw; cancellation still consumes none; the modal restore event and authoritative visibility/status redraw remain unchanged. Monster rows are N/A.

Known behavior explicitly out of scope:
Wearability rules, starting equipment, takeoff/eat/quaff, spell item selection beyond preserving its explicit hint, command-key case, item descriptions, and generic overlay refactoring.

Unresolved uncertainty and risk:
The stale current_overlay decision and overwritten return are proven statically. Direct-letter and `?` behavior still require Virtual ][ confirmation because the Apple harness has no item scenario.
```

### M3 takeoff equipment-overlay return repair record — 2026-07-22

```text
Problem and success criteria:
Takeoff has the same invalid window return when `?` opens its equipment list. Success is that `T`, `?`, and a listed item return to OVL.ITEMS, remove the selected non-cursed item under the existing rules, update status/equipment, and remain responsive; ESC cancel and direct letters remain unchanged.

State being changed:
Apple physical overlay ownership after the takeoff equipment modal only. Equipment records, curse rules, pack capacity, recalculation, text, and turn behavior are unchanged.

Search scope and terms:
item_takeoff; show_equip_and_select; tramp_ui_equip_select_display; ui_view_restore_modal_overlay; tier_restore_after_overlay; OVL.HELP; OVL.ITEMS; all show_equip_and_select callers; and the wear inventory-overlay return repair.

Relevant readers/writers found and known exclusions:
item_takeoff is the sole show_equip_and_select caller and executes in OVL.ITEMS. show_equip_and_select is resident, but after it restores the tier it directly RTSes to the overwritten OVL.ITEMS continuation. Unlike show_inv_and_select it has no reload step. Direct-letter takeoff never opens OVL.HELP and is excluded.

Initialization, reset and persistence points:
N/A — no new state or persistence.

Affected production sequence through the changed transition:
T in OVL.ITEMS -> `?` -> OVL.HELP equipment list -> capture key -> resident checked ITEMS modal-restore wrapper -> restore tier and gameplay view -> reload boot-cached OVL.ITEMS -> return through resident show_equip_and_select to item_takeoff -> existing validation/removal.

Contract decision or selected upstream oracle with source locations:
The exclusive window ownership in docs/APPLE2_MEMORY_POLICY.md and the sole-caller result make OVL.ITEMS the required physical owner. Existing direct-letter takeoff is the semantic oracle. The wear and spell-list resident restore boundaries are the structural oracle.

Intentional Moria8 deviations:
N/A.

Input/intermediate widths, signedness, carry, range and overflow policy:
Selection keys and slots remain unsigned bytes with existing masks and bounds. The modal restore preserves nothing by contract; the captured key remains protected on the stack. No item arithmetic changes.

RNG reduction and bias, if applicable:
N/A — takeoff uses no RNG.

Affected platforms, overlays, banks and owners:
Apple only. show_equip_and_select conditionally calls a new entry in the shared resident reload epilogue; Commodore output remains on its existing direct restore path.

Required production-path tests:
Full build; Apple memory contract and disk; emitted inspection proving the Apple equipment-list path calls the resident wrapper, which reloads OVL.ITEMS. Runtime: direct and `?` takeoff, ESC, cursed refusal if available, equipment/status refresh, and next command. Turn/Render rows remain the existing success=one turn/full redraw and cancel=zero turn behavior; monster rows are N/A.

Known behavior explicitly out of scope:
Wear, takeoff rules/balance, curse generation, pack-full behavior changes, item descriptions, and generic modal refactoring.

Unresolved uncertainty and risk:
The overwritten return is proven statically; runtime selection remains manual until the Apple harness gains an item scenario.
```

### M3 ego item-description overlay-independence repair record — 2026-07-22

```text
Problem and success criteria:
After shop activity, wear/inventory behavior varies between an ignored command, a screen with only the Inventory title, and a hang. The partial Inventory symptom must render every listed item and remain responsive regardless of whether the pack/store contains an ego item. Store and inventory descriptions must retain their full ego suffix text without loading or executing a different code overlay.

State being changed:
Apple presentation-time ego-suffix storage and lookup only. Ego IDs, generation, combat modifiers, equipment effects, item records, identification, suffix wording, turn behavior, and save representation are unchanged.

Search scope and terms:
The reported post-shop/Inventory sequence; ui_inv_select_display; store_draw_screen; itemdesc_put_inv_slot; itemdesc_put_store_slot; itemdesc_put_staged; banked_ego_put_suffix; ego_get_suffix_ptr; ego_suffix_lo/hi; ego strings; OVL.HELP; OVL.TOWN; OVL.ITEMS; current_overlay; all banked_ego_put_suffix callers; and the earlier ego-trampoline ownership record.

Relevant readers/writers found and known exclusions:
ui_inventory.s and ui_store.s execute from OVL.HELP and OVL.TOWN respectively. Both call the resident item-description formatter, which calls banked_ego_put_suffix in persistent A2.PLAY for every non-tool item. For a nonzero ego, that routine directly calls ego_get_suffix_ptr, but Apple emits ego_get_suffix_ptr and all suffix strings in OVL.ITEMS. Neither caller loads ITEMS, and doing so would overwrite its own HELP/TOWN continuation. Ego zero returns before the invalid call, so the failure depends on the generated/purchased item mix and can appear only after the Inventory title or some rows. The four persistent trampoline-placement guards do not cover this direct call. Keyboard command mapping and the separate fresh-key path are excluded from this ownership repair.

Initialization, reset and persistence points:
No mutable state is added. An immutable, page-aligned Apple copy of the eight suffix slots is emitted in A2AuxData and loaded by the existing boot payload. Slot zero and unused padding are zero-filled.

Affected production sequence through the changed transition:
Store or inventory/equipment renderer in its current overlay -> resident item-description formatter -> persistent banked_ego_put_suffix -> compute the fixed 16-byte aux slot from ego ID -> read characters through the existing aux-safe thunk -> render through hal_screen_put_char -> return to the unchanged HELP/TOWN continuation.

Contract decision or selected upstream oracle with source locations:
docs/APPLE2_MEMORY_POLICY.md makes the $A400-$B9FF overlays mutually exclusive; therefore persistent code cannot directly call an implementation/data pointer owned by a different overlay and then return to the overwritten caller. platforms/apple2/mmu_macros.s and memory_aux.s define the aux-safe read path. core/ego_items.s is the exact player-visible suffix-text oracle. Existing ego-zero and valid-range checks remain authoritative.

Intentional Moria8 deviations:
N/A — the Apple copy preserves every existing suffix byte and only changes physical ownership.

Input/intermediate widths, signedness, carry, range and overflow policy:
Ego IDs remain unsigned bytes 0-7. Valid nonzero IDs are multiplied by 16, producing aux-page offsets $10-$70 without overflow. Every slot is exactly 16 bytes including terminator/padding; the longest ` (Holy Avenger)` string plus terminator is exactly 16. The aux thunk and Apple screen writer preserve X, which is the bounded 0-15 character index. Carry has no caller-visible result.

RNG reduction and bias, if applicable:
N/A — ego generation and all RNG calls are unchanged.

Affected platforms, overlays, banks and owners:
Apple only. The new immutable suffix slots live in A2AuxData below its $5700 ceiling. The Apple banked_ego_put_suffix branch stays in A2.PLAY and must remain at or below $9FFF. OVL.ITEMS keeps its original ego strings for generation/combat consumers. C64/C128/Plus4 output retains the existing direct pointer implementation.

Required production-path tests:
Full cross-platform build; Apple memory contract/self-test and disk regeneration; emitted extents proving A2.PLAY <= $9FFF and A2AuxData <= $56FF; emitted inspection proving Apple banked_ego_put_suffix calls mmu_safe_map_read_ptr0 and no longer calls ego_get_suffix_ptr. Runtime gate: visit a shop, exercise a store containing ego stock if available, leave, open inventory/wear, render all rows and suffixes, select/cancel, and accept subsequent commands without partial title or hang. Turn/Render rows: pure presentation consumes authoritative item/ego state and changes no turn, visibility, dirty-event, repeat-command, modal-restore, or status semantics. Monster rows are N/A.

Known behavior explicitly out of scope:
Whether uppercase ASCII W is intentionally a shifted/unmapped command on Apple, host Caps Lock behavior, general input loss during redraw, ego balance/generation, non-ego item selection, and generic overlay architecture.

Unresolved uncertainty and risk:
The cross-overlay call is proven statically and precisely explains item-mix-dependent partial rendering/hangs. No new stopped snapshot yet proves that the current reported hang PC is this call, and the ignored-W observation may be an independent input/case issue. The requested Virtual ][ snapshots remain the runtime oracle.
```

### M3 follow-up/selectable initiating-key repair record — 2026-07-22

```text
Problem and success criteria:
The Apple wear selection flashes and returns to gameplay without waiting for an item key. An initial repair rejected repeated `?` only after a full-screen list; the unchanged runtime result disproved that as the complete failure path. Success is that `W` leaves the wearable-item prompt waiting for a fresh item key, `?` leaves its displayed list active until a non-`?` selection or cancel key arrives, and the bounded Apple key-release fallback that prevents the earlier character-selection deadlock remains intact.

State being changed:
Apple follow-up-key preparation and selectable-overlay input classification only. No persistent state, item/spell data, modal contents, turn state, dirty flags, equipment effects, or spell effects change.

Search scope and terms:
input_prepare_followup_key; hal_input_followup_prepare; every preparation call site and its following key read; input_prepare_selectable_overlay_key; input_get_followup_key; input_wait_release; input_modal_prepare; show_inv_and_select; show_equip_and_select; pm_prompt_visible_spell_choice; piw_select_filtered_inv; item_wear; and all show_inv_and_select/show_equip_and_select callers.

Relevant readers/writers found and known exclusions:
The wear command enters piw_select_filtered_inv, prints the wearable-item prompt, calls input_prepare_followup_key, and immediately reads the item key. Apple mapped hal_input_followup_prepare to input_noop, so a held or host-repeated `W` can be accepted as the choice; `W` lies outside the visible A-V range and takes the existing cancel return, exactly matching the flash. Other follow-up call sites have the same stated fresh-key requirement. Read-only help dismissal already uses modal preparation and is excluded. The three selectable full-screen lists additionally enter with `?`; the existing Apple release record documents that the bounded AKD fallback can still allow a held initiating key into the later prompt, and `?` is never a valid list choice.

Initialization, reset and persistence points:
N/A — no new state is introduced. Follow-up preparation reuses the existing bounded modal-release routine, and `?` rejection remains local to each selectable-overlay key read.

Affected production sequence through the changed transition:
Gameplay command key -> follow-up prompt -> bounded Apple release preparation -> wait for the new answer key. For list selection: W/T/cast/pray prompt -> `?` -> bounded release preparation -> draw the appropriate selectable overlay -> read keys while rejecting `?` -> accept a letter, SPACE, ESC, or CTRL+C under the existing caller rules -> restore the tier/gameplay view and required physical overlay -> continue or cancel normally.

Contract decision or selected upstream oracle with source locations:
core/input_ui_helpers.s defines input_prepare_followup_key as ensuring that an initiating command does not leak into a secondary prompt. Mapping that contract to a no-op violates its stated semantics. platforms/apple2/input.s already supplies input_modal_prepare/input_wait_release as the bounded fresh-key implementation, including the demonstrated Virtual ][ deadlock fallback. core/player_item_select.s and core/player_magic.s define `?` as the command to open a list, not as a list choice. Existing direct-letter selector behavior remains the semantic oracle.

Intentional Moria8 deviations:
N/A — this prevents an initiating command key from being misclassified as a list choice.

Input/intermediate widths, signedness, carry, range and overflow policy:
Keys remain unsigned bytes. Follow-up preparation changes no returned key. Only byte `$3F` is retried on Apple after a selectable overlay has been drawn. Existing letter normalization, SPACE cancellation, ESC/CTRL+C handling, carry results, and selection bounds are unchanged.

RNG reduction and bias, if applicable:
N/A — input/modal handling uses no gameplay RNG.

Affected platforms, overlays, banks and owners:
Apple behavior only. The Apple follow-up HAL alias now targets the existing resident bounded modal-preparation routine. A resident Apple helper serves inventory, equipment, and spell-list reads. To stay within the resident window, the Apple inventory return-owner check is reduced to the immediate caller return address; the complete caller search proves every no-hint Apple caller is either immediately resident or immediately in OVL.ITEMS, while OVL.SPELL supplies an explicit hint. Commodore code generation and ownership inference remain unchanged.

Required production-path tests:
Full cross-platform build; Apple memory-contract checker and regenerated disk; emitted inspection proving the Apple follow-up alias targets bounded modal preparation, all three Apple selectable lists call the retry helper, and the no-hint inventory owner check still distinguishes resident from OVL.ITEMS. Exact runtime gate: press `W` and release it; the item prompt must remain without another key. Then `?` must remain on the list without another key, and a listed letter must equip and return responsive gameplay; ESC must cancel. Additional manual coverage: direct-letter wear, `T`/`?`, cast/pray `?`, and another secondary prompt. Turn/Render rows are unchanged: only an initiating key is drained before existing selection/cancel behavior; no turn, visibility, dirty, redraw, repeat-command, status, or monster-authority rule changes.

Known behavior explicitly out of scope:
General Apple keyboard typematic policy, item/spell availability and effects, help content, and generic modal refactoring.

Unresolved uncertainty and risk:
The unchanged result disproves repeated `?` as the complete diagnosis. The no-op follow-up path can produce the exact observed return, but the repeated `W` value is inferred because no stopped snapshot captured igk_key. The bounded fallback deliberately permits progress if AKD remains asserted and therefore cannot guarantee release under that exceptional emulator state; list-level `?` rejection covers the reported nested selector. Virtual ][ confirmation remains the authoritative runtime gate.
```

### M3 generation busy-screen blanking repair — 2026-07-22

```text
The Apple II blanking primitive previously switched to hires page 1 while the
generation UI cleared text memory. That page is not initialized by the boot
path, so Virtual ][ and MAME could display arbitrary bitmap bytes as a full
screen of garbage. screen_blank now forces full-screen text mode; the existing
text clear and generation repaint sequence is unchanged. This is Apple display
ownership only: gameplay state, turn behavior, and text rendering semantics do
not change. Verification: clean diskapple2 build (305 asserts) and Apple
memory-contract check (21/21).
```

### M3 item-action dispatch-policy repair — 2026-07-22

```text
Problem and success criteria:
The initial W command cleared the message rows and returned without a prompt or
message. Success is that every item-action command enters OVL.ITEMS through its
resident trampoline; W with no wearable pack item reports the existing
"You have nothing there." message; and W with a wearable item waits, supports
the ? inventory list, equips the selection, and returns to command input.

Evidence and corrected root cause:
Apple defined hal_platform_game_loop_item_actions_trampolined as an assembler
constant, but core/game_loop.s selects the trampoline path with the uppercase
HAL_PLATFORM_GAME_LOOP_ITEM_ACTIONS_TRAMPOLINED preprocessor symbol. The symbol
was absent. The linked cmd_wear therefore called item_wear at $A9E8 directly
while OVL.GEN still owned $A400-$B9FF in town. This record supersedes the
initiating-key hypothesis as the explanation for the initial W failure; the
separate modal-return repairs remain applicable to nested ? selection.

Changed state and invariants:
Apple lifecycle policy now defines the selector used by game_loop. No gameplay,
inventory, input, turn-consumption, redraw, item-rule, or save state changes.
The affected W/T/E/Q commands retain their existing semantics and byte lengths;
only their JSR targets change to resident overlay-loading trampolines.

Focused verification:
A clean `make clean diskapple2` completed with 305 main-image and 6 boot-image
assertions, all passing. The clean A2.PLAY links W/T/E/Q to $7A32/$7A3D/$7A48/
$7A53. A production-path MAME run reached town and verified both branches:
starting inventory W displayed "You have nothing there." and returned to input;
a diagnostic wearable item produced the wear prompt, ? rendered the complete
inventory, selection moved the item into its equipment slot, printed the wield
message, and returned to input. Turn/Render and Monster contract rows are N/A:
the existing item implementations and their state/turn/redraw behavior are
unchanged; this repair only restores their physical overlay entry boundary.

Known exclusions:
General help content, magic/prayer behavior, item-selection rules, emulator ROM
warnings, and generic overlay refactoring.
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

### M4 record — 2026-07-23

```text
Scope:
M4 polish, performance, and release verification: runtime scenario coverage
(priest prayer, help, wizard, dungeon descent, death, save/load roundtrip),
the repairs those scenarios exposed, sound/title-art verification, aux cache
assessment, and strategy-document reconciliation.

Repairs delivered under this record:

1. Prayer/cast book selection (reported as "'p' not activating the prayer").
   tramp_select_filtered_inv destroyed the filter (A) and prompt id (X)
   through overlay_load before calling piw_select_filtered_inv, so every
   book was rejected with "You have nothing there." The trampoline now
   preserves both registers; a shared OVL.SPELL epilogue was deduplicated to
   hold the $7C00 resident boundary. priests start with the Beginners
   Handbook (game_loop.s starting-gear grant, verified in inventory).

2. '?' spell/prayer list garbage (garbled names, wrong mana/level).
   spell_list_display read name pointer tables owned by OVL.UI while
   OVL.SPELL was loaded, and read aux mana/level tables with direct
   main-RAM reads. spell_names.s moved to A2AuxData; all four table reads
   now go through MapRead thunks; names print char-by-char through the aux
   thunk on Apple II.

3. Wizard item generation wild jump ("You feel heroic!" instead of "OK").
   wizard_generate_item_execute lives in OVL.MODAL; tramp_roll_ego_type
   loaded OVL.ITEMS and returned into evicted memory, so execution fell
   into the quaff-effect dispatch. New tramp_roll_ego_type_modal restores
   OVL.MODAL before returning; 19 identical OVL.ITEMS trampolines were
   deduplicated into a shared indirect dispatch to hold the resident
   boundary.

Runtime scenarios (permanent regression coverage in
platforms/apple2/harness_smoke.py, all green):
boot_title (7), priest_pray (8), help_overlay (3), wizard_flow (4),
dungeon_descend (4), death_flow (2), save_load (9). The save/load roundtrip
writes THE.GAME, returns to title, lists the saved character in the slot
UI, and reloads with stats restored. Notable verified-correct behaviors
initially mistaken for defects: the player intentionally spawns left of
the town stairs (classic Moria), and starting-inventory W shows "You have
nothing there." because all wearables start equipped.

Sound: synchronous speaker clicks at $C030 verified at runtime (new-game
SFX_PICKUP produces 32 speaker toggles on the tapped line).

Title art: aux art buffer verified populated and dense (577 nonzero bytes,
rows 0-9), with clean row 0 in both text halves.

Aux cache: manifest v7 assessed — hot classes fill aux $5000-$BFFF at
28,587/28,672 B with cold classes on disk; overlay transitions in all
scenarios resolve from cache. No tuning changes; further work needs
hit-rate evidence, not speculation.

Docs: CROSS_PLATFORM_STRATEGY.md ca65 migration note superseded (Kick
Assembler retained per in-tree precedent); its "all overlays preloaded"
claim corrected to the partial aux cache with disk-on-demand cold classes.
ARCHITECTURE.md gained an Apple IIe Runtime Model section.

Environment:
MAME 0.288 apple2ee runs headless (-video none). The boot hang reported as
"corrupt ROMs" was a missing 341-0028-a Disk II P6 LSS PROM plus the
341-0132-d AY3600 keyboard decode ROM; a working set was assembled from
local dumps, with the keyboard table synthesized from the AY3600 matrix
encoding (QWERTY half verified, revised-Dvorak half per ANSI layout).

Verification:
make testapple2-memory-contract 21/21; make build all platforms; C64
179/179; C128 full 135/135; Plus/4 36/36; C64/C128/Plus4 spell-prayer
subsets green; all seven Apple II MAME scenarios green.
```

### M4 wizard gain-level overlay-routing repair record — 2026-07-24

```text
Problem and success criteria:
Wizard gain level (X) printed garbage and could run wild on Apple II (user
report: garbage message line, level applied). Success is the level-up message
("Welcome to level N."), an advanced LV status field, an intact wizard/gameplay
continuation, and permanent harness regression coverage.

State being changed:
Overlay-window routing of the combat_apply_levelup magic-helper calls, and
ownership of the wizard gain-level continuation. Gameplay values, thresholds,
and formulas are unchanged.

Search scope and terms:
ui_wizard gain-level flow, combat_apply_levelup,
tramp_magic_recalc_mana/check_new_spells, overlay_load skip/cache policy,
Kick Assembler #if/.const semantics, established modal-return trampolines
(bash OVL.ITEMS restore, wizard-item OVL.MODAL restore), MAME CPU trace of the
faulting run.

Relevant readers/writers found and known exclusions:
The user-visible garbage traced (MAME instruction trace) to combat_apply_levelup
executing jsr $b485 / jsr $b276 DIRECTLY into the overlay window: the source
guard `#if hal_platform_levelup_magic_uses_trampoline` never worked, because
Kick Assembler's #if preprocessor cannot see assembler .const values (verified
empirically with Kick 5.25: #if on a .const silently takes the #else arm; #if on
a #define and .if on a .const both work). With OVL.MODAL loaded, those addresses
hold modal bytes, so execution went wild into Applesoft ROM. C128 emitted the
same direct calls unnoticed because its magic helpers live in the always-mapped
$F000 runtime. The play-resident wizard.s duplicate is safe (continuation in
play); excluded. Other `#if <lowercase .const>` sites exist in core (ui_restore,
ui_messages, ui_character, player, player_move, player_magic_ball) and are a
separate audit item, not changed here.

Initialization, reset and persistence points:
current_overlay becomes OVL.SPELL during the level-up helpers and is restored
to OVL.MODAL before the wizard continuation runs; no persisted state changes.

Affected production sequence through the changed transition:
tramp_ui_wizard_display (loads OVL.MODAL) -> ui_wizard_display -> X ->
ui_wizard_cmd_gain_level -> restore_gameplay_view -> combat_apply_levelup ->
tramp_magic_recalc_mana / tramp_magic_check_new_spells (load OVL.SPELL, return)
-> message/sound -> tramp_combat_apply_levelup_modal reloads OVL.MODAL ->
status_draw -> rts into the restored modal overlay.

Contract decision or selected upstream oracle with source locations:
docs/APPLE2_MEMORY_POLICY.md exclusive $A400-$B9FF window ownership (one
overlay or the tier at a time); the bash (tramp_combat_check_levelup_items) and
wizard-item (tramp_roll_ego_type_modal) repair precedents for restoring the
caller overlay before returning; COMMODORE_HAL_RESTRUCTURE.md slice 38, which
documents the C128 bank-safe trampoline as the intended level-up path that this
repair actually activates.

Intentional Moria8 deviations:
None.

Input/intermediate widths, signedness, carry, range and overflow policy:
N/A (code routing only; no values changed).

RNG reduction and bias, if applicable:
N/A.

Affected platforms, overlays, banks and owners:
All four platforms assemble combat.s. C64/Plus4 keep direct calls (policy
const 0; emitted PRGs verified byte-identical by md5). C128 now routes through
its documented bank-safe trampolines (restores pre-restructure behavior).
Apple II routes through OVL.SPELL-loading trampolines plus the new resident
tramp_combat_apply_levelup_modal restoring OVL.MODAL for the wizard
continuation. check_hal_lifecycle_exports.py gained the const/#define pair
entry for the new flag, following the existing tuple pattern.

Required production-path tests:
harness_smoke.py wizard_flow extended: after item generation, reopen the
wizard menu, press X, assert "Welcome to level" renders and the status line
advances to LV:2 (7 asserts). The scenario executes the real
overlay/trampoline/renderer path on the shipping binary.

Known behavior explicitly out of scope:
The remaining `#if <lowercase .const>` sites listed above (separate audit).
The synthesized AY3600 keyboard ROM in the local MAME romset emits lowercase
ASCII for unshifted letters; input_translate normalizes it, so the harness
must use press() (not shift()) for menu letters.

Unresolved uncertainty and risk:
None blocking. C128 gate evidence: make test128-fast 152 pass lines, no
failures; make test128-fast-smoke 10/10; apple2 memory-contract 21/21; all
eight MAME scenarios green (wizard_flow now 7 asserts); C64/Plus4 PRGs
byte-identical; check_hal_lifecycle_exports/check_6502_lint/check_zp_usage
green.

Harness note (same change): the MAME smoke harness replaced the osascript
window-hiding hack with SDL_VIDEODRIVER=dummy/SDL_AUDIODRIVER=dummy so
headless runs never create a window or take focus.
```

## 2026-07-25 — Commodore-parity Disk Setup (multi-drive + swap)

Problem and success criteria:
Disk Setup was a degenerate no-UI probe (`a2_disk_setup_run`: marker probe
plus silent auto-init) and every layer assumed the boot volume. Success:
title `D` runs a guided Disk Setup matching the Commodore flow — menu with
volume summary, pick a save volume from an ON_LINE enumeration, one-drive
swap mode with insert-disk prompts, marker init prompt, program-media
rejection, classified init-failure detail — and save/load/death flows honor
the selected save volume. Maintainer decisions (this task): full parity,
plus a "1) Game disk" menu option so saving on the game disk stays legal
(Commodore has no such option).

State being changed:
`save_device`/`program_device` are now real ProDOS unit bytes (drive/slot
nibbles) resolved by ON_LINE; new resident `a2_save_volume` /
`a2_program_volume` (16-byte len-prefixed names); `disk_mode` gains
platform-owned values `A2_DISK_MODE_GAME`=1 (save volume == program
volume), `A2_DISK_MODE_TWO_DRIVE`=2, `A2_DISK_MODE_SWAP`=3 (separate
volume sharing the program unit). Verified no shared code interprets
`disk_mode` values (all value readers are Commodore-only files). New
Apple-local `disk_ui_*` mailbox in `disk_setup_a2.s` with the same numeric
action/result assignments as the Commodore `DISK_UI_*` consts.

Storage routing rule:
All save-side filenames already carry a `0:`/`S0:`/`@0:` prefix and every
program asset name is prefix-free, so `a2_mli_set_pathname` treats a
consumed drive prefix as the save-volume selector: when `disk_mode >= 2`
it emits an absolute `/VOLUME/FILE` pathname (ProDOS resolves the volume
on whichever unit holds it); otherwise names stay relative to the boot
prefix exactly as before. `a2_map_media_error` now classifies `$45`
(volume not found) and `$2E` (disk switched) as WRONG_MEDIA — the mounted
media is not the expected volume — so `save_game`'s existing
`tramp_disk_prepare_selected` recovery fires on swap errors.

Architecture:
Coordinator + UI live in OVL.STORAGE (`disk_setup_a2.s`, overlay slack was
~3.1 KB) alongside save.s, mirroring `disk_setup_banked.s`; all ON_LINE /
GET_PREFIX primitives, volume scan/list helpers, and the pick list live
there too because resident space was byte-tight (24 B slack at HEAD). The
runtime swap prompts (`disk_prompt_save`/`disk_prompt_game`) are resident
in main.s like the Commodore originals — callers run with arbitrary
overlays live (death flow keeps OVL.DEATH), so no overlay loads may happen
there; they probe via the resident marker/program GET_FILE_INFO probes
instead of ON_LINE. An earlier trampoline draft that loaded OVL.STORAGE
from the prompts clobbered OVL.DEATH mid-death-flow and skipped the
tombstone; caught by `death_flow` and corrected. `a2_title_stage` now
aliases `a2_ss_buf` (title staging, ON_LINE reports, and save streams are
never open concurrently), reclaiming 256 resident bytes; resident ends
$7B9A (166 B slack). /RAM (unit $B0) is excluded from enumeration per the
existing no-/RAM aux policy.

Runtime flows:
In-game save, title load, and death/hiscore paths use the shared
`disk_prompt_save` / `disk_prompt_game_required` call sites unchanged
(Commodore parity: title_load gained the same `disk_prompt_save` +
`disk_prompt_game` + `disk_prompt_game_required` calls as c64 main.s).
One-drive swap setup ends with an "Insert program disk" restore prompt so
title/play payloads are always loadable afterward.

Required production-path tests (all on the shipping binary):
- `disk_setup_two_drive` (9 asserts): menu, volume summary, ON_LINE pick
  list with slot/drive display, save-volume selection, marker init prompt;
  host-side AppleCommander check proves `MORIA8.ID` landed on the SAVE1
  image (blank `-flop2` created per run).
- `disk_setup_swap` (10 asserts): single-drive pick-list rescan after a
  Lua floppy swap, program-media rejection, insert-save prompt, marker
  init, program-disk restore prompt; same host-side marker proof.
- `save_load` and `death_flow` updated to drive the setup menu once via
  `disk_mode`/`disk_setup_done` RAM state (pixels cannot distinguish
  "menu awaiting input" from "prepare busy"), then go through the
  unchanged slot/death flows. Long-hold `press_slow` added after MAME
  dropped short key holds during drive activity.

Known behavior explicitly out of scope:
Write-protect/disk-full init-failure detail paths (classified strings
exist; no harness coverage — MAME lacks a simple per-image write-protect
toggle). `hal_storage_disk_setup_supports_other_drive` stays 0: the
Commodore checker-facing policy predates this feature and the Apple UI is
platform-native, not the shared `ui_disk_setup.s`.

Unresolved uncertainty and risk:
None blocking. Verification: clean `make build` (all platforms, 306 Apple
asserts 0 failed); apple2 memory-contract 21/21; all ten MAME scenarios
green (boot_title 7, priest_pray 8, help_overlay 3, wizard_flow 7,
dungeon_descend 4, death_flow 2, save_load 9, disk_setup_two_drive 9,
disk_setup_swap 10). No shared or Commodore files touched.

### 2026-07-25 follow-up — insert-save loop learned to adopt media

User report: with a blank or different disk on the save unit, prepare
looped forever on "Insert save disk" and never offered "Initialize this
disk?" — the save-volume check required an exact ON_LINE name match, so
any other media was invisible. `a2_disk_prepare_selected` now examines
whatever is mounted on the save unit (true Commodore semantics): the
program disk is rejected ("Program disk cannot hold saves.", re-shown
while it stays mounted), any other ProDOS volume is adopted as the save
volume, and unreadable media (unformatted/non-ProDOS, including ON_LINE
zero-length-name entries, which also guarded the pick list and the
len-0 pathname fallback after a wrong-volume commit was observed) goes
straight to the init offer, where init fails honestly with the classified
detail line. New helper `a2_volume_on_unit` in disk_setup_a2.s. New
`disk_setup_adopt` scenario (13 asserts): SAVE1 replaced by SAVE2 ->
adopted + init offered + host marker proof on SAVE2; SAVE2 replaced by a
zeroed image -> init offered -> "Could not initialize disk." + "Check the
disk and try again." -> back to menu. `disk_setup_swap` updated for the
stickier rejection. Full suite re-run green.

### 2026-07-25 follow-up 2 — pick list shows unreadable drives again

User report: the pick list no longer showed a disk present in drive 2. The
zero-length/error-entry guards had made unreadable media (unformatted,
non-ProDOS) vanish from the list entirely. Commodore lets the player pick
a drive regardless of contents, so the pick list now shows such units as
selectable "<not ProDOS> (Sx,Dy)" entries (len byte $ff in the list
buffer). Selecting one stores a nameless save volume; prepare's init
offer then fails honestly, and a new guard keeps marker_init from ever
falling back to a relative pathname on the program volume for a nameless
selection (wrong-volume write hazard). a2_scan_volume also rejects
nameless targets outright. disk_setup_adopt phase 3 (18 asserts total)
covers listing, selection, init offer, and classified failure for the
unreadable drive.

### 2026-07-25 follow-up 3 — strict parity: no saves on the game disk

Maintainer decision: saves never live on the game disk, matching the
Commodore ports exactly (upgrade safety; the game disk can stay
write-protected). This supersedes the earlier "parity + game-disk option"
choice in this task. Capacity also forces it: the game image has ~16 KB
free and one save is ~15.7 KB, so a full slot set (~63 KB) cannot fit.

Changes: the menu is now "1) One drive (swap) / 2) Pick save drive /
3) Done / Q) Back"; A2_DISK_MODE_GAME and the game-disk prepare branch
are gone; the default selection is one-drive on the program unit
(nameless until the save disk is inserted; the summary shows the unit);
a picked program volume is rejected at prepare ("Program disk cannot
hold saves.") even when online. Mode is computed from units only
(same unit = swap, different = two-drive). One-drive flow: insert prompt
-> adopt whatever ProDOS volume is inserted / reject the game disk /
init offer, ending with the program-disk restore prompt.

Harness: save_load and death_flow now run with SAVE1 mounted as -flop2
and drive the pick flow (rescan gate, /SAVE1 summary gate, disk_mode RAM
gate); save_load adds host-side proof that THE.GAME landed on SAVE1.
ds_save_default asserts the one-drive unit summary. Full suite re-run
green (boot_title 7, priest_pray 8, help_overlay 3, wizard_flow 7,
dungeon_descend 4, death_flow 2, save_load 10, disk_setup_two_drive 9,
disk_setup_swap 10, disk_setup_adopt 18); memory contract 21/21; clean
make build.

### 2026-07-25 follow-up 4 — cold-boot load crash (play-slot ordering)

User report: save+load worked in-session but failed after a reboot. Root
cause: the strict-parity title_load flow called `disk_prompt_game` and
`disk_prompt_game_required` before `a2_require_play` — and
`disk_prompt_game_required` lives in game_loop.s, which is play-slot code
on this platform. After a cold boot the play slot is not loaded, so the
call executed garbage; in-session the slot was already resident, masking
it (HEAD evidence: pre-feature single-drive reboot-load passes; current
build failed deterministically). Fix: resident `disk_prompt_game` first,
then `a2_require_play`, then the play-slot verifier. Regression coverage:
new two-session `save_reboot_load` scenario (9 asserts: save in session
A, cold-boot load in session B, plus host proof THE.GAME is on SAVE1).
Diagnosis note: an early trace marker was itself clobbering A before the
asset loader's filename push, producing a phantom 210-byte pathname; the
trace evidence from those builds was discarded and the marker fixed.
Full suite re-run green (11 scenarios + save_reboot_load); memory
contract 21/21; clean make build.

### 2026-07-25 follow-up 5 — save-slot tracking ownership

Task: track which save slot was loaded from, matching the Commodore
semantics (fe30f3d slot support + 3b2cd86 deliberate clear on title
return). Two Apple-specific ownership defects found and fixed:

1. save_slot_index was declared inside the shared save engine, which
   lives in the OVL.STORAGE window on this platform — any overlay swap
   (descend, cast, store) silently reset the loaded slot. On C64/Plus4
   the engine sits in the $F000 banked region; on C128 it is resident.
   Fix: SAVE_SLOT_INDEX_EXTERNAL guard in shared save.s; the byte is
   platform-declared.
2. The first resident placement ($0A07) still read back aux data after
   dungeon code left RAMRD on: every address >= $0200 is RAMRD/RAMWRT
   bank-switched on the IIe, so the slot menu's read hit the aux map byte
   at the same address. Fix: the byte is now unbanked platform ZP ($aa).

Regression coverage: save_slot_tracking scenario (9 asserts) — save slot
2, title, load slot 2, descend to DL:1 (overlay + tier loads + map
writes), then the in-game save menu must mark slot 2 with '*' and the
re-save must land THE.GAME2 on SAVE1 (host proof). A/B-verified: with
the byte in the overlay window the marker is forgotten after the
descend; with the ZP byte it survives. Full suite + build + memory
contract green.

### 2026-07-25 follow-up 6 — program-media rejection escape

User report: "Program disk cannot hold saves." looped forever with no way
back to the menu. The prepare flow re-showed the rejection without the
intervening insert prompt and had no cancel. Now the rejection alternates
with the insert-save prompt (Commodore's INSERT_DISK / SHOW_PROGRAM
rhythm), and the insert prompt cancels to the menu on Q or ESC (hint
string shown). The setup-run fail path returns to the menu; the
wrong-media recovery fail path fails the save with a status message.
disk_setup_swap extended (13 asserts): alternation, Q escape to the menu,
rejection persistence, and the normal swap flow. Full suite green.

### 2026-07-25 follow-up 7 — press-key hint visibility

User question: the program-media rejection showed no "Press any key"
hint. The Commodore rejection screen shows the message and the hint on
one screen, then alternates with the insert prompt — two screens, each
with its own hint; the Apple flow now matches that exactly. The hint was
missing because the a2ds screens printed the shared press_key_str, which
lives in game_loop.s — play-slot code, not loaded when Disk Setup runs at
title. The a2ds screens now use a local copy of the same text. Verified
on screen: "Program disk cannot hold saves." + "Press any key".

### 2026-07-25 performance audit — scrolling & monster updates

Read-only audit of the viewport-scroll and monster-update hot paths. Audit
method: static call-chain tracing with hand-counted 6502 cycle estimates
(~1.023 MHz), NOT harness profiles; relative ratios are robust, absolute
numbers are estimates. C128 findings from the same audit live in
docs/C128_PERFORMANCE.md. Nothing below has been implemented; items P1-P8
are tracked candidates pending approval.

#### A2 viewport scrolling — bottlenecks

1. Full 78x18 = 1404-cell redraw (~0.3 s) is the ONLY scroll path; no
   scroll-delta (HAL_PLATFORM_GAME_LOOP_SCROLL_DELTA_RENDER = 0,
   platforms/apple2/hal/lifecycle_policy.s:37). turn_scene_dirty — any
   visible monster move outside the light radius
   (core/game_loop.s:1357-1363) — triggers the same full redraw, nearly
   every combat turn.
2. 28 cy per map byte: the map lives in AUX, every read toggles RAMRD
   twice through a ZP thunk (platforms/apple2/memory_aux.s:47-52) — ~39k
   cy/redraw vs C64's ~7k for the same reads.
3. glyph_find_at runs for every lit cell even when zero glyphs exist
   (~85 cy x ~1400 cells, up to ~120k cy/redraw,
   platforms/apple2/dungeon_render_a2.s:336). Shared with C64, but A2
   pays it on 1.9x more cells.
4. a2_map_char is a ~27-cy branch chain
   (platforms/apple2/screen_a2.s:100-145) instead of a table; plus a
   php/plp parity shuffle per cell — ~80 cy/cell staging total.

#### A2 monster updates — why slower than C64/C128

Monster AI logic is shared core code; the slowdown is trigger frequency
x redraw cost:

- Any monster visibility-flag change sets vis_room_revealed=1
  (core/dungeon_los.s:198-202) -> full redraw. Monsters entering/leaving
  torchlight — routine in combat — fire this. C64 full-redraws every step
  anyway (no deadband), so monster-driven redraws are free there but cost
  A2 ~0.3 s each. The perceived "monsters are slow" is this asymmetry.
- AUX-resident Huffman strings make every attack/spell message decode
  ~10x more expensive (~40 cy/tree-step vs 4 on C64,
  platforms/apple2/mmu_macros.s:70-84). Scales with monster count.
- All map access in AI/LOS paths is thunked (~1.7x C64), including
  per-LOS-step reads for up to 32 monsters every turn
  (core/dungeon_los.s:198).

#### Candidate improvements — tracked, not approved

| # | Change | Platform | Size | Est. impact | Gate |
|---|--------|----------|------|-------------|------|
| P1 | ~~Glyph/item-scan early-out (active-count gate)~~ DONE 2026-07-25 | all | small | up to ~120k cy/A2 redraw | make test64 + A2 suite |
| P2 | ~~Per-row AUX map block read (a2_thunk_read_block, memory_aux.s:55-64)~~ DONE 2026-07-25 | A2 | small | ~28k cy/redraw | A2 suite |
| P4 | ~~A2 scroll-delta render (shift viewport in place + render exposed strip)~~ DONE 2026-07-27 | A2 | large | ~300k -> ~40k cy/scroll | TURN_RENDER contract + A2 suite |
| P5 | Tile-level scene-dirty list in core (replace full redraw for mat_scene_dirty) | core/all | large | monster turns: ~2 cells instead of 1404 | TURN_RENDER contract + all suites |
| P6 | a2_map_char -> 256-byte table | A2 | small | ~20 cy/cell; costs most resident slack (~$98 free at $7B9E) | memory contract |
| P8 | X-split cell-write loops (drop per-cell parity shuffle) | A2 | small | ~15 cy/cell | A2 suite |

(P3 and P7 are C128 items; see docs/C128_PERFORMANCE.md.)

Suggested order: P1+P2 (low-risk wins), then P3, then P4, then P5.

### 2026-07-25 P1+P2 implemented — render early-outs and AUX row block read

Change record (Routine tier — implementation under the settled TURN_RENDER
contract; no state, lifecycle, or representation change; rendered output is
byte-identical by construction):

- Problem: per-cell glyph_find_at scans ran even when no warding glyphs
  exist (~85 cy x cells); the C128 rescanned all 42 floor-item slots per
  row even when empty; the A2 paid a 28-cy AUX thunk per map byte.
- Success criterion: identical pixels; fewer cycles; all existing gates
  pass. Invariant: TURN_RENDER renderer-consumer convergence — every gate
  skips only a provably empty scan. zp_item_count is already maintained by
  floor item add/remove (core/item.s) and recount on load (save.s).
- Changes:
  - P1a glyph gate: render_viewport on A2/C64/Plus4 caches "any
    glyph_active" once per row and skips the per-cell glyph_find_at when
    zero; C128 inlines the same OR at its single glyph site (RuntimeLowData
    had no room for a cache byte — the resident scratch region sits 3
    bytes under FLOOR_ITEM_BASE, found via the boundary assert).
  - P1b C128 item gate: rv_populate_row_items returns after zeroing the
    occupancy row when zp_item_count = 0.
  - P2 A2 row block read: render_viewport block-reads the 78-byte map row
    slice from AUX once per row (new mmu_safe_map_read_block wrapper over
    the previously unused A2_ZP_THUNK_READ_BLOCK) into a row buffer;
    per-cell read becomes lda buf,y. The row buffer aliases a2_ss_buf
    (same disjoint-lifetime argument as a2_title_stage: save streams,
    title staging, and gameplay rendering never run concurrently; the
    slice is refilled every row). Resident end: $7BC4 ($3C slack).
  - Test scaffolding: render tests that stub glyph_find_at alias or
    zero-fill glyph_active (0 => stub always misses, so the skip is
    output-equivalent).
- Verification: make build (all platforms, 0 assert failures); make
  test64 179/179; make testplus4 36/36; TEST_FILTER=vdc_scroll_delta128
  and main_loop128 make test128 PASS; make test128-fast PASS; A2 harness
  all 13 scenarios green.

Estimated savings (hand-counted, per full A2 redraw): glyph gate up to
~120k cy, row block read ~28k cy. C128: ~4k cy/row item+scan overhead
when empty, ~60 cy/cell glyph scan.

### 2026-07-27 P4 implemented — A2 scroll-delta viewport rendering

Change record (Routine tier — implementation under the settled
TURN_RENDER contract; delta path must converge on full-redraw output):

- Problem: every viewport scroll (deadband crossing) and every
  non-local visible monster move forced a full 78x18 = 1404-cell
  render_viewport (~0.3 s at ~1 MHz).
- Change: render_viewport_scroll_delta (new
  platforms/apple2/dungeon_scroll_a2.s, in the play slot) shifts the
  displayed 80-column text page in place for clean 1-tile single-axis
  scrolls and redraws only the exposed strip via render_single_tile;
  HAL_PLATFORM_GAME_LOOP_SCROLL_DELTA_RENDER now defined for A2
  (hal/lifecycle_policy.s). Anything else (scene dirty, room reveal,
  multi-tile) still falls back to full redraw, matching the C128
  contract.
- Mechanics: 80STORE+PAGE2 selects main/aux text halves at $0400
  without banking code fetch, so the shift loops run from the play
  slot. Horizontal shifts stage both 40-byte halves of each row into
  rv_row_map_buf (a2_ss_buf idle-lifetime alias) and rewrite from the
  staging buffer — direct in-place shifting is impossible because the
  even/odd interleave makes overlapping main->aux copies clobber
  sources. Vertical shifts copy row-to-row per half-plane, no staging.
  Border columns and the exposed-strip column are never copied.
- Space: the play slot was full ($A000 exact). Freed by moving the
  recall-view (monster memory) command body to ModalMiscOverlay
  (RecallViewBodySegment macros; invocation guarded so other platforms
  need no definitions) and by externalizing the welcome/search/stairs
  message strings to A2AuxData read via a2_msg_print_indirect_aux
  (MsgPrintStr macro in game_loop.s). Cache slots resized
  (SPELL $7900, MODAL $8D00; all payloads fit with >=62B slack).
  Play slot ends $9FFF (1 byte slack).
- Bug found and fixed by poke test: the first H-shift implementation
  indexed text-page halves by column (1..79) instead of half-index
  (0..39), addressing screen holes; caught by a poke-pattern MAME test
  (zero mismatches after the fix).
- Harness: new scroll_delta scenario (descend, wizard teleport, walk
  until horizontal scroll, assert every non-local cell equals the
  pre-scroll cell one column right).
- Related infrastructure fix: the A2 boot loader PRG depended only on
  boot.s, not cache_layout.s, so the cache slot move left the boot-time
  aux-cache population using stale addresses while overlay_load read
  the new ones (SPELL/MODAL overlays loaded zeros). Makefile dependency
  added; caught by priest_pray/mage_list/wizard_flow/death_flow
  scenario failures.
- Verification: poke-pattern shift test (0 mismatches), scroll_delta
  scenario PASS, full A2 harness all 14 scenarios green; make build
  clean; test64 179/179; testplus4 36/36; test128-fast PASS.

Estimated cost per scroll: H ~40k cycles, V ~37k cycles (vs ~300k
full redraw), plus exposed-strip redraw. The ~7.5x speedup comes from
not recomputing cells: a full redraw pays ~210 cy/cell (AUX thunked
map read ~28 cy, tile-flag decode, overlays, a2_map_char ~27 cy,
parity shuffle) for all 1404 cells, while a scroll only relocates
already-rendered bytes (~14 cy/byte-op) and recomputes the newly
exposed edge. The full cost model is in dungeon_scroll_a2.s.

### 2026-07-27 P4 follow-up — V-scroll half-row overflow fix

User report: scrolling jumbled the dungeon and status screens (off-by-1/
off-by-2). Root cause: the vertical row copy in a2sd_copy_plane used
`cpy #VIEWPORT_W + 1` (79), copying 78 bytes per half-row — but a text
half-row is only 40 bytes. Because the Apple II text page interleaves
row groups (rows 0-7, 8-15, 16-23 at $80 strides with $28 group
offsets), a 78-byte copy from row r overflows 38 bytes past the half-row
into *other visible rows*: e.g. dst row 16 ($450) overflows into the
message row 1 ($480 = $450+$30), and higher dst rows overflow into the
status rows 20-23. Result: status fragments at wrong rows and status
rows themselves overwritten by neighbouring viewport rows.

Fix: a2sd_copy_plane now copies exactly the 40-byte half-row
(`ldy #0 / cpy #A2_HALF_ROW`). Border columns are permanent spaces by
renderer design, so copying the full half-row (including borders) is
harmless and keeps the copy two toggles per row.

Verification: the previously corrupt V-scroll frame (status shifted
into rows 1/21-23) now renders clean; poke-pattern H-shift test still
0 mismatches; scroll_delta scenario extended with a v_no_status_leak
regression assert (no status text outside the status rows after a
vertical scroll); full A2 harness all 14 scenarios green; make build
clean.

### 2026-07-28 P5 implemented — tile-level scene-dirty rendering

Change record (Routine tier — implementation under the settled
TURN_RENDER contract; final screen state must be identical to the
full-redraw behavior it replaces).

- Problem: every visible/detected monster move outside the player's
  local light footprint forced a full 1404-cell viewport redraw each
  such turn (the "monsters feel slow" hot path, ~300k cycles on A2).
- Design: mat_mark_tile_dirty_if_nonlocal (the single hot producer)
  immediate-renders the changed tile at mark time via the new
  scene_render_mat_tile helper (render_single_tile + set the
  mat_scene_dirty aggregate). The scene-dirty render dispatch
  (game_loop !scene_dirty_redraw) then uses the cheap path — only the
  player's local box via render_local_area — iff the turn's dirt is
  provably already rendered (mat_scene_dirty set). Everything else
  (combat kills, spell tile effects, forced-full command tails via
  scene_force_full_redraw, search aggregation, earthquake/reveal)
  still takes the full fallback; scene_force_full_redraw vetoes the
  cheap path by clearing mat_scene_dirty. turn_scene_dirty
  semantics for repeat/stop logic are unchanged.
- Auto-run regression (found by maintainer): the veto originally
  incremented zp_dirty_count, but that latch is consumed by the NEXT
  turn's turn_post_action into turn_scene_dirty, and run-step stop
  logic reads turn_scene_dirty every step — the leak cancelled
  auto-run after one step. The clear-mat veto leaves no latch, so
  run-step turn_scene_dirty reflects only monster activity, exactly
  as before P5. With the veto no longer touching zp_dirty_count,
  that latch is provably always clear at dispatch (all its producers
  run mid-turn and are consumed by turn_post_action), so the
  dispatch's zp_dirty_count guard was removed as dead code.
- Correctness edges: visibility-flag changes (monster entering/leaving
  view) are covered by the existing reveal path (full redraw); scrolls
  and reveals override the scene branch entirely; the cheap path only
  fires when the ONLY dirt is mat's already-rendered tiles.
- Critical bug found by harness: render_single_tile must save and
  restore zp_ptr0/zp_ptr0_hi across its body. The render's internal
  monster_find_at iterates all monsters through monster_get_ptr (and on
  A2 the AUX map read uses zp_ptr0 as its pointer), clobbering the AI
  loop's monster-record pointer and changing monster behavior (and the
  downstream RNG stream) — empirically proven by the teleport landing
  shifting until the save/restore was added. The dance lives inside
  render_single_tile itself on all four platforms (cheaper than
  preserving at every call site).
- mat_scene_dirty is now a counter (inc per immediate tile render; one
  monster move marks old+new tile = 2). Consumers only test nonzero.
  test_monster_ai test 27 updated from cmp #1 to cmp #2 (stronger:
  verifies both old and new tiles get marked).
- Memory: razor-thin but fits. scene_dirty_check + scene_mat_tile +
  scene_force in Default on C64/Plus4; on C128 scene_force lives in
  C128ResidentItems, mat in Default, and the dirty check is inlined in
  game_loop.s under #if C128 (using the unconditional scene_full_fallback
  / scene_post_move aliases, since !full_draw_fallback only exists under
  HAL_PLATFORM_GAME_LOOP_SCROLL_DELTA_RENDER). On A2, scene_render_mat_tile
  is a fall-through label into render_single_tile in dungeon_render_a2.s
  (saves jsr+rts; A2 Default was 3B over $7C00 with a standalone helper).
- Verification: make build clean all platforms, test64 179/179 (incl.
  search forced-full case 5), testplus4 36/36, test128-fast PASS,
  test128 135/135 (authoritative; C128 layout changed), A2 harness all
  14 scenarios green (dungeon_descend, scroll_delta included).
