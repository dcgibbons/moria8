# Commodore Headroom Report

Date: 2026-03-25

Scope:
- `commodore/c64`
- `commodore/c128`

Method:
- rebuilt the live C64 and C128 assemblies with KickAssembler
- used `out/main.vs` symbol files for exact end-label addresses
- used `commodore/c128/memory128.s` as the Bank 1 ownership manifest

Measurement notes:
- KickAssembler end labels such as `program_end`, `banked_payload_end`, `ovl_*_end`, and `runtime_low_data_end` are treated as next-free addresses
- manifest constants in `memory128.s` such as `BANK1_*_END` are inclusive endpoints
- reported slack is therefore:
  - `limit - next_free` for symbol-based regions
  - `next_base - inclusive_end - 1` for manifest gap checks

## Executive Summary

Highest-risk regions right now:
- C64 runtime banked code: `4` bytes below `$FFFA`
- C64 staged banked payload source: `5` bytes below `$D000`
- C64 main image: `40` bytes below `MAP_BASE`
- C64 startup overlay: `44` bytes below `$F000`
- C128 `RuntimeLowData`: `0` bytes below floor-item storage at `$1A00`
- C128 staged source / program image: `79` bytes below `$E000`
- C128 startup overlay: `35` bytes below `$F000`

Interpretation:
- C64 is past “tight” and into active budget management
- C128 Bank 0 is generally healthier, but a few low-memory and overlay boundaries are already effectively hard ceilings
- most C128 Bank 1 transitions are deliberate zero-gap ownership boundaries, not spare capacity

## C64 Exact Margins

| Region | Measured end | Limit | Slack bytes | Risk |
|---|---:|---:|---:|---|
| Main program image | `$BFD8` | `$C000` | `40` | Critical |
| Staged banked payload source | `$CFFB` | `$D000` | `5` | Critical |
| Runtime banked payload | `$FFF6` | `$FFFA` | `4` | Critical |
| Startup overlay | `$EFD4` | `$F000` | `44` | High |
| DungeonGen overlay | `$EBF6` | `$F000` | `1034` | Moderate |
| Town overlay | `$EBC8` | `$F000` | `1080` | Moderate |
| Death overlay | `$E5B5` | `$F000` | `2635` | Low |

Notes:
- `program_end = $BFD8` means the current build leaves only `40` bytes before the live map at `$C000`
- the banked payload source region is effectively full; five more bytes reach the I/O hole boundary
- the runtime banked payload still fits, but only `4` bytes remain before the CPU vectors

## C128 Exact Margins

### Bank 0 / Staged Source / Overlay Windows

| Region | Measured end | Limit | Slack bytes | Risk |
|---|---:|---:|---:|---|
| Program image / staged source span | `$DFB1` | `$E000` | `79` | High |
| Staged banked payload source | `$DFB1` | `$E000` | `79` | High |
| Runtime banked payload | `$FB94` | `$FFFA` | `1126` | Low |
| `RuntimeLowData` below floor items | `$1A00` | `$1A00` | `0` | Critical |
| Startup overlay | `$EFDD` | `$F000` | `35` | High |
| UI overlay | `$EEF8` | `$F000` | `264` | Moderate |
| DungeonGen overlay | `$EE63` | `$F000` | `413` | Moderate |
| Town overlay | `$EBE9` | `$F000` | `1047` | Moderate |
| Death overlay | `$E5B5` | `$F000` | `2635` | Low |
| Cache state block | `$32F5` | `$E000` | `44299` | Low |
| Overlay state block inside cache state block | `$32ED` | `$32F5` | `8` | Low |

Notes:
- `RuntimeLowData` is exactly flush with `FLOOR_ITEM_BASE = $1A00`; any growth there must move the floor-item table or shrink the low-runtime payload
- the staged source / program image margin to `$E000` is now `79` bytes after phase 9 `LINT-1`
- the startup overlay is the tightest C128 overlay at `35` bytes of remaining space
- the staged source / program image margin to `$E000` is still finite and should be tracked because it gates boot-time copy safety
- the phase-4 wrapper fix reduced the C128 staged-source / program-image margin from `148` bytes to `76`, phase 5 `API-1` reduced it again to `73`, phase 6 `CA-12` reduced it further to `54`, and phase 9 `LINT-1` recovered it to `79`

### Bank 1 Ownership Manifest

| Region | Address span | Size bytes | Gap before next region |
|---|---|---:|---:|
| Common RAM | `$0000-$0FFF` | `4096` | `0` |
| UI overlay cache | `$1000-$1FFF` | `4096` | `0` |
| Reclaimed low | `$2000-$3FFF` | `8192` | `0` |
| Reserved future map span | `$4000-$730B` | `13068` | `244` |
| DB region | `$7400-$7FFF` | `3072` | `0` |
| Tier cache window | `$8000-$94F7` | `5368` | `0` |
| Reserved gap 0 | `$94F8-$9FFF` | `2824` | `0` |
| STARTUP overlay cache | `$A000-$AFFF` | `4096` | `0` |
| TOWN overlay cache | `$B000-$BFFF` | `4096` | `0` |
| DEATH overlay cache | `$C000-$CFFF` | `4096` | `0` |
| Reserved I/O-visible gap | `$D000-$DFFF` | `4096` | `0` |
| DUNGEON overlay cache | `$E000-$EFFF` | `4096` | `0` |
| Reserved top gap | `$F000-$FEFF` | `3840` | n/a |

Notes:
- the only unassigned slack between hard-owned Bank 1 regions is the `244`-byte hole between the future-map reservation and the DB region
- `Reserved gap 0` and the reserved top gap are intentional policy reserves, not accidental free space
- the many `0`-byte transitions are by design; they mean the ownership map is packed contiguously and growth requires an explicit reallocation decision

## Ranking

1. C128 `RuntimeLowData` at `0` bytes slack
2. C64 runtime banked payload at `4` bytes slack
3. C64 staged banked payload source at `5` bytes slack
4. C128 startup overlay at `35` bytes slack
5. C64 main program image at `40` bytes slack
6. C64 startup overlay at `44` bytes slack
7. C128 staged source / program image at `79` bytes slack
8. C128 Bank 1 future-map to DB hole at `244` bytes of unassigned room
9. C128 UI overlay at `264` bytes slack
10. C128 DungeonGen overlay at `413` bytes slack

## Recommendation

Short-term governance actions:
- treat C64 main, C64 banked payload, C64 startup overlay, and C128 `RuntimeLowData` as explicit change-control zones
- add one generated headroom summary to the build so these margins are visible without reading scattered `.assert`s
- require any new C64 feature work to identify its byte budget up front
- require any C128 low-runtime change to state what moves if `RuntimeLowData` grows past `$1A00`
