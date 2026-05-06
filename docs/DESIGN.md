# Design Reference

Moria8 adapts Umoria to machines with far less directly usable memory and a
different display model than the original 80-column terminal game. The C64
target defines the tightest budget; the C128 target adds banked memory, 80-column
VDC rendering, and a more involved boot/load model while preserving shared game
logic where practical.

## Core Constraints

Umoria's data footprint is roughly 90-110 KB before considering runtime state.
A stock C64 has about 38 KB of straightforward RAM after screen, color, ROM, and
system areas are accounted for. The port therefore reduces and tiers data,
keeps the live map compact on C64, and uses disk or REU paths for content that
does not need to be resident all the time.

The display is also narrower. C64 gameplay is designed for 40 columns. C128
gameplay can use VDC 80-column display paths, but the shared game UI must still
respect 40-column-era text and layout constraints where shared code is used.

## C64 Memory Budget

| Region | Address | Use |
|---|---:|---|
| Zero page | `$02-$8F` | Game-owned hot variables, with KERNAL caller-save discipline where needed |
| Program | `$0801-$BFFF` | BASIC stub, resident code, resident data, RAM under BASIC ROM |
| Map | `$C000-$CEFF` | 80x48 compact dungeon map |
| Floor items | `$CF00-$CFFF` | Fixed floor-item table |
| I/O | `$D000-$DFFF` | Device window; not ordinary executable/readable RAM with I/O visible |
| Overlays | `$E000-$EFFF` | Runtime overlay window |
| Banked runtime | `$F000-$FFFA` | Permanent banked code/data below CPU vectors |

The main segment must stay below `$C000`. The banked payload must stay below
`$FFFA`. Overlay segments must fit in `$E000-$EFFF`.

## Dungeon Map

The original Moria map is too large for the C64 target. The C64 runtime uses an
80x48 map represented as one byte per tile, with bit fields for terrain, light,
knowledge, item presence, and monster presence.

Tile item and monster bits are presence flags. Identity is resolved by scanning
the active monster table or floor item table for matching coordinates. This
keeps the map compact and makes the limited always-visible RAM region usable.

The C128 target stores the live dungeon/town map in Bank 1 RAM and supports the
larger current runtime map geometry used by the C128 code path.

## Creatures

Creature data is tiered by dungeon depth. Town creatures are always available;
dungeon tiers are loaded when the player crosses tier boundaries. On C64, tiers
can be loaded from disk or fetched from REU when available. On C128, tier data
uses the documented Bank 1 cache and runtime ownership model.

The implementation uses struct-of-arrays data for compactness and efficient
6502 indexing. Only one dungeon tier is copied into the active creature buffer
at a time; the C128 can cache the dungeon tiers in Bank 1.

## Items

The current item set is intentionally smaller than Umoria's full data set and
fits in resident program data. Carried inventory is a dense prefix: removing an
item compacts later carried items so pack letters match visible order.
Equipment remains fixed-slot and does not compact.

Ego metadata and magic bonuses are split into compact resident fields and
sidecar arrays where that saves space or simplifies save/load ownership.

## Text

The port keeps text compact and uppercase-friendly for Commodore display modes.
New shared UI and game-world text should prefer the existing string-bank and
Huffman paths unless a code path demonstrably requires direct raw string
ownership.

User-visible text is not scratch space for memory recovery. If a build exceeds a
segment or overlay boundary, fix ownership, layout, code duplication, or data
placement before shortening player-facing strings.

## UI

C64 gameplay uses a 40-column screen with message rows, viewport, status rows,
and prompts. Messages use a small queue and a `-more-` marker when needed.

The C128 VDC renderer must preserve display semantics between full redraws and
single-tile updates. Items, monsters, glyphs, and player overlays must keep the
same precedence in both paths.

## Deferred Areas

Moria8 is not a byte-for-byte Umoria reproduction. Deferred or reduced areas
include the full original content breadth, monster recall persistence, custom
fastloader work, and long-term polish tasks.
