# C128 Memory And Banking Contract

Load this document for C128 address placement, MMU or `$01` banking, overlays,
runtime-loaded/copied code, caches, KERNAL transitions, or physical VDC access.
Do not load it for shared gameplay changes that neither alter payload layout nor
touch C128-specific memory services.

`platforms/commodore/c128/memory128.s` is the executable runtime ownership
authority. `platforms/commodore/c128/boot128.s` is the executable authority for
boot-copy modes, physical copy/scrub bounds, and staging transitions. This
document summarizes both. Address changes must update the owning source and its
assertions, not only this table.

## Runtime Modes

| Mode | Configuration | Contract |
| --- | --- | --- |
| Startup/KERNAL | `MMU_NORMAL=$0e` | Bank 0, BASIC removed, system ROM and I/O visible |
| Operational Bank 0 | `MMU_ALL_RAM=$3e` | Bank 0 RAM, I/O visible; KERNAL reached through RAM stubs |
| Bank 1 data/cache | `MMU_RAM_BANK1=$7e` | Bank 1 RAM, I/O visible |
| Boot copy source | `MMU_RAM_BANK1_NOIO=$7f` | Bank 1 RAM with RAM, not I/O, visible at `$d000-$dfff` |
| Boot copy destination | `MMU_ALL_RAM_NOIO=$3f` | Bank 0 RAM with RAM, not I/O, visible at `$d000-$dfff` |

During normal runtime, bit 2 of `$01` stays set. MMU configuration bit 0 also
controls whether I/O or RAM is exposed at `$d000-$dfff`; boot copy deliberately
uses the no-I/O modes above. Access under KERNAL ROM requires the established
interrupt-safe helpers; raw bank changes must not bypass their save/restore
discipline.

## Bank 1 Ownership Snapshot

This is a descriptive snapshot checked 2026-07-09. `memory128.s` constants and
overlap assertions are the executable authority; never edit this table alone.

| Span | Owner/lifetime |
| --- | --- |
| `$0000-$0fff` | common RAM; shared, not cache-safe |
| `$1000-$1fff` | UI overlay cache |
| `$2000-$2fff` | HELP overlay cache |
| `$3000-$3fff` | ITEMS overlay cache |
| `$4000-$730b` | reserved 198x66 live map span |
| `$730c-$73ff` | reserved unowned gap between map and DB regions |
| `$7400-$7a5f` | DB/data region: the `128.names` payload, `it_name_lo` then the item-name streams, which end it at `$79e6`, with 121 bytes to grow (`main.s` asserts the payload's true end; its segment max is `$7a5f`). `it_unknown_idx` moved to `128.item` on 2026-11-07 |
| `$7a60-$9567` | the monster catalog (C128M-007): `$7a60-$7e5f` the name pool, 32 species slots x 32 B written at species fetch; `$7e60-$9542` `128.cat`, the catalog's 21 fields x 279 creatures, loaded at boot; 37 B spare. Until 2026-11-02 the tier cache, 6920 bytes |
| `$9568-$97ff` | title marker/data cache (663 data bytes; the title art needs 593-624) |
| `$9800-$9cff` | MODAL small-overlay cache |
| `$9d00-$9fff` | DISARM small-overlay cache |
| `$a000-$afff` | `128.cnm`, the catalog's Huffman-coded names (tree, pointers, bitstreams; 3380 B), loaded at boot (C128M-007). Until 2026-11-02 the STARTUP overlay cache: STARTUP now loads from disk |
| `$b000-$bfff` | TOWN overlay cache |
| `$c000-$cfff` | DEATH overlay cache |
| `$d000-$dfff` | post-boot runtime I/O-visible gap; never runtime cache/data RAM |
| `$e000-$efff` | DUNGEON overlay cache |
| `$f000-$feff` | runtime top-common view shared with Bank 0; physical Bank 1 `$f000-$fd3a` owns the read-only Huffman corpus, exposed only by the atomic Huffman helpers |
| `$fffa-$fffb` | physical Bank 1 NMI vector bridge used only during transient Huffman reads with top common disabled |

The staged PRG payload begins at `$1c01`, but the page copier physically reads
and scrubs Bank 1 `$1c00-$feff`, including RAM under
`$d000-$dfff` while a no-I/O mode is selected. This is the sole documented
exception to the post-boot runtime ownership table. The copy-to-Bank-0 process
scrubs staged pages. Cache validity cannot be assumed until the relevant cache
has been repopulated and marked valid.

Important Bank 0 ownership includes the resident payloads (`128.world`
`$6000-$8c4f`, `128.item` `$8c50-$a7ff`, `128.select` `$a800-$aaff`, each
segment's max the next one's start; the always-resident `128.diskio` holds the
modal footer `press_key_str` and the death message `slain_str`, C128M-006), floor items at `$1a00-$1aff`, runtime
scratch at `$1b00-$1bff`, the overlay window at `$e000-$efff`, and reloadable
banked code at `$f000` below `$ff00`. `main.s` assertions are authoritative for
resident segment starts and ends.

## Required Change Record

For CPU-memory ownership, address, MMU, load, or copy changes, complete
applicable fields and mark safety-critical irrelevant fields `N/A` with
evidence. A VDC-only change uses the explicit VDC record below instead.

```text
symbol/payload and linked segment:
PRG load header:
source and destination spans:
source/destination bank and lifetime:
MMU/$01 configuration at load, copy, execution and return:
common-RAM and interrupt/vector assumptions:
KERNAL transition path:
overlapping owners and guarding assertions:
production runtime test:
```

Unknown bank visibility, ownership, copy survival or return state blocks the
change. A correct linked address alone is insufficient.

## Physical VDC Contract

VDC screen and attribute memory are not CPU RAM. Changes must identify active
VDC register, internal source/destination address, row stride, copy direction,
ready polling, and whether horizontal/vertical paths share equivalent bounds.
Shared map coordinates must not depend on VDC physical layout.

```text
active VDC register(s):
internal source and destination addresses:
screen/attribute base and row stride:
copy direction, length, and overlap policy:
ready-polling and interrupt assumptions:
horizontal/vertical bound equivalence:
production runtime test:
```

## Failure Interpretation

Presume a memory-contract defect until disproved for CPU JAM, moving crash
addresses after byte-size changes, blank map with valid UI, overlay-specific
corruption, horizontal/vertical VDC divergence, save corruption after layout
work, or a new runtime timeout.

## Verification Matrix

| Change | Required gate |
| --- | --- |
| Any C128 layout change | `make build`, assembler map/prints, all ownership assertions |
| Overlay/cache/load/copy change | linked symbol, PRG header, banks and spans inspected; focused production runtime test |
| Broad banking/MMU/runtime-loaded change | `make test128-fast-smoke`, then authoritative `make test128` |
| Physical VDC change | horizontal, vertical, copied-interior and stale-tile production tests |
| Shared payload composition | affected C64 and Plus/4 build/runtime gates |

A test importing a routine at a convenient address proves its logic, not its
C128 memory contract.

## Executable Enforcement

| Invariant | Current gate | Command/status |
| --- | --- | --- |
| Bank isolation, IRQ-state preservation, and CPU-memory row-copy helpers | `platforms/commodore/c128/tests/test_memory128.s` | `TEST_FILTER='memory128' make test128` |
| Bank 1 ownership and resident/overlay bounds | `.assert` blocks in `memory128.s` and `main.s` | `make build` |
| Built payloads: each PRG at its segment's start and within its max, resident Bank 0 windows and bytes pairwise disjoint, `128.names` inside the DB region and before the tier cache | `tools/check_c128_payloads.py` (the bytes emitted, not end labels: both 2026-10-26 overruns passed label asserts) | `make check128-payloads`; runs before `make test128` and `make test128-fast-smoke` |
| Overlay/cache runtime behavior | `cache_survival_smoke`, `preload_partial_failure_smoke`, `overlay_partial_failure_smoke`, `overlay_data_transition_smoke` | `TEST_FILTER='cache' make test128`, then authoritative `make test128` for broad changes |
| VDC copy/scroll physical behavior | `platforms/commodore/c128/tests/test_vdc_scroll_delta128.s` | `TEST_FILTER='vdc_scroll_delta128' make test128` |
| Complete normal/no-I/O MMU and KERNAL transition matrix | none | `NOT IMPLEMENTED` |

## Decision Ledger

Accepted rows dated 2026-07-09 record explicit maintainer decisions from the
work16 C128 memory review; this ledger is their durable approval provenance.

| ID | Status | Owner/date | Scope and selected rule | Evidence/enforcement | Supersedes |
| --- | --- | --- | --- | --- | --- |
| C128M-001 | Accepted | Project maintainer, 2026-07-09 | `memory128.s` constants/assertions are executable ownership authority | `make build`, `test_memory128.s` | prose-only ownership |
| C128M-002 | Accepted | Project maintainer, 2026-07-09 | After boot staging is scrubbed, `$d000-$dfff` remains an I/O-visible reserved runtime/cache gap in Bank 1; no-I/O boot staging is the explicit temporary exception | maintainer decision; overlap assertions; boot-copy mode review | none |
| C128M-003 | Accepted | Project maintainer, 2026-07-09 | New cache/map/common-RAM use requires a separate layout design and overlap assertions | build assertions and authoritative `make test128` | none |
| C128M-004 | Accepted | Project maintainer, 2026-08-12 | Modal-misc overlay gets a Bank 1 cache slot at `$9800-$9CFF`, carved from title-cache slack (title art needs 593-624 B of the former 1928 B cache); overlay cache covers IDs 1-9 with a second ready-bit byte | maintainer direction this session; `memory128.s` overlap asserts; `cache_survival_smoke` and partial-failure smokes | none |
| C128M-005 | Accepted | Project maintainer, 2026-10-25 | Store init/restock (`store_restock_overlay.s`) moves from the items overlay (ID 7, full after store stacking) to the cold chest overlay (ID 10); `tramp_store_init_all`/`tramp_store_restock_all` load ID 10, a disk load at new game and town re-entry. Bank 1 has no free slot to cache ID 10 (largest free span: 244 B at `$730C`). Maintainer: "I don't want the load, but let's do it for now." | `main.s` ID assert and overlay-fit asserts; `make test128` | cache ID 10 if Bank 1 space is found |
| C128M-007 | Accepted | Project maintainer, 2026-11-02 | The monster catalog replaces the tiers (`docs/MONSTER_CATALOG_DESIGN.md`): it takes the tier cache window (name pool, then `128.cat` fields) and the STARTUP overlay slot (`128.cnm` names, Huffman-coded with their own tree). STARTUP is no longer cached: New Game loads it from disk. The level index is resident in `128.world`; the fetch reads Bank 1 through the safe DB and Huffman helpers. Names on disk were declined unless needed. Maintainer: "let's not cache the start overlay. and then huffman-code the names, but avoid #2 unless we need to." | `memory128.s` catalog spans and overlap asserts; `main.s` segment asserts; `make check128-payloads`; `catalog_spawn_smoke`, `cache_survival_smoke`; `make test128` | C128M-004's STARTUP cache slot; the tier cache |
| C128M-006 | Accepted | Project maintainer, 2026-10-31 | `slain_str` ("You have been slain.", 21 B, read-only, read only by Bank 0 `core/game_loop.s`) moves from `128.item` to the always-resident `128.diskio`, beside `press_key_str`, because the 33-slot inventory arrays (+16 B) would overflow `128.item` by 3 B. `128.item` keeps 18 B free; `128.diskio` 30 B (21 B in the tightest test variant) | `docs/X_WEAPON_SWAP_DESIGN.md` §3.5 and §14 answer 1; `main.s` asserts `slain_str` lies inside the disk-I/O payload; `make check128-payloads`; `make test128` | none |
| C128M-008 | Proposed (awaiting maintainer review) | 2026-11-09 | The program-media probe (`disk_program_media_present`, `c128_program_play_exists`, `c128_ppe_tries`, `c128_program_read_command_status`, `c128_program_play_read_filename`; 201 B of Bank 0 code and data, called only from Bank 0 resident code) moves from `128.item` to `128.world`, because 16-item stores (+224 B of store arrays) overflowed `128.item` by 166 B. Both payloads are always resident in Bank 0 and `128.world` loads first (`c128_load_core_residents`), so the probe is present at least as early as before. `128.world` now ends at `$8B58` (247 B free), `128.item` at `$A7DC` (35 B free) | `main.s` asserts the probe lies inside the world payload; `make check128-payloads`; `make test128` | none |
