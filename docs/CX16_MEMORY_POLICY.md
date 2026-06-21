# Commander X16 Memory Policy

This document is the human-readable companion to the enforced constants in
`platforms/cx16/memory.s` and `platforms/cx16/check_memory_contract.py`.

## Fixed RAM

The normal CX16 product PRG loads at `$0801`; machine code starts at `$0810`.
Resident code must stay below `MAP_BASE`, currently `$6800`.

| Region | Address range | Owner | Lifecycle |
| --- | --- | --- | --- |
| Zero page / KERNAL workspace | `$0000-$03FF` | KERNAL, zero page, stack-adjacent runtime | Always visible; not general heap |
| Dungeon-gen BFS queue | `$0400-$07FF` | shared dungeon generator | Temporary during generation |
| Resident product image | `$0801-$67FF` | CX16 fixed code/data | Always visible |
| Live map | `$6800-$9B0B` | shared map, 198x66 | Current town/dungeon state |
| Floor item table | `$9C00-$9CFF` | shared floor-item runtime | Current level state |
| Creature scratch | `$9D00-$9DFF` | CX16 creature/runtime scratch | Current level state |
| Huffman decode buffer | `$9E00-$9EFF` | shared Huffman decoder | Temporary text decode |
| VERA/I/O hole | `$9F00-$9FFF` | hardware I/O | Never RAM-owned |

The live map remains fixed RAM because the shared 198x66 map is 13,068 bytes,
larger than one 8 KiB CX16 banked-RAM window. Moving it to banked RAM requires
a deliberate split-window map accessor, not direct substitution.

## Banked RAM

The baseline target is 512 KiB banked RAM, exposed as 64 banks of 8 KiB at
`$A000-$BFFF`. Bank selection is through the CX16 RAM-bank register at `$00`.

| Bank(s) | Owner class | Current concrete payload | Lifecycle |
| --- | --- | --- | --- |
| 0 | Default/system visible bank | none | Not persistent cache storage |
| 1-3 | Transient scratch | smoke-test guard/copy banks today | Caller-owned; payload may be destroyed |
| 4-7 | Monster tier cache | `MONSTER.DB.1` through `MONSTER.DB.4` | Preloaded before title; persistent |
| 8 | Executable module cache | `DUNGEON.GEN` | Preloaded before title; persistent |
| 9-10 | Item catalog family | `ITEMCAT.1` in bank 9; bank 10 reserved for item text/extra split | Preloaded before title; persistent |
| 11 | Title-art source | `TITLE` | Loaded by title renderer; reloadable staging/source |
| 12 | Code-overlay slot | `X16.START` marker sidecar | Preloaded before title; payload migration pending |
| 13 | Code-overlay slot | `X16.TOWN` marker sidecar | Preloaded before title; payload migration pending |
| 14 | Code-overlay slot | `X16.DEATH` marker sidecar | Preloaded before title; payload migration pending |
| 15 | Code-overlay slot | `X16.ROYAL` marker sidecar | Preloaded before title; payload migration pending |
| 16 | Code-overlay slot | `X16.GEN` marker sidecar | Preloaded before title; current `DUNGEON.GEN` remains bank 8 |
| 17 | Code-overlay slot | `X16.HELP` marker sidecar | Preloaded before title; payload migration pending |
| 18 | Code-overlay slot | `X16.UI` marker sidecar | Preloaded before title; payload migration pending |
| 19 | Code-overlay slot | `X16.ITEMS` marker sidecar | Preloaded before title; payload migration pending |
| 20 | Code-overlay slot | `X16.SPELL` marker sidecar | Preloaded before title; payload migration pending |
| 21 | Code-overlay slot | `X16.DISARM` marker sidecar | Preloaded before title; payload migration pending |
| 22-31 | Code-overlay expansion class | unallocated | Reserved for future resident overlays/modules |
| 32-47 | Immutable-data/string cache class | unallocated | Reserved for future data and string banks |
| 48-63 | Work/cache class | unallocated | Reserved for save/load, generation, and temporary work |

## Allocation Rules

1. New persistent bank ownership must be represented by named constants in
   `platforms/cx16/memory.s`.
2. New persistent bank ownership must be exported as `cx16_contract_*` labels
   from `platforms/cx16/main.s`.
3. New persistent bank ownership must be validated by
   `platforms/cx16/check_memory_contract.py`.
4. Bank 0 is never a persistent cache.
5. Banks 1-3 and 48-63 are scratch by class. Code using them must assume the
   contents do not survive calls into unrelated subsystems.
6. Shared game code must not write `$00` or read/write `$A000-$BFFF` directly.
   Platform-owned helpers must select, scope, and restore the active RAM bank.
7. Product resident code must stay below `MAP_BASE` unless the code is emitted
   as an explicit `$A000-$BFFF` bank-window PRG/module.
8. The title-art load address is `$A000` for CX16. It must not return to a
   fixed-RAM staging address such as `$6000`, because that would pin resident
   code below the staging address again.
9. Named overlay banks have emitted CX16 sidecar PRGs and loader entries. The
   current sidecars are marker payloads that prove build/load/cache ownership;
   migrate real shared overlay code into them deliberately, one ownership
   boundary at a time.

## Verification

`make testcx16-memory-contract` is the static policy gate. It validates the
assembled product symbols, PRG spans, title/tier/module/item/overlay
bank-window payload spans, and the bank class layout above.

`make testcx16` is the runtime gate. It additionally boots the product in
`x16emu`, verifies the bank-window loaders, and checks that the title, tier,
dungeon module, and item-catalog paths preserve caller bank selection.
