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
| `$7400-$7fff` | DB/data region |
| `$8000-$94f7` | tier cache, 5368 bytes |
| `$94f8-$9cff` | title marker/data cache |
| `$9d00-$9fff` | DISARM small-overlay cache |
| `$a000-$afff` | STARTUP overlay cache |
| `$b000-$bfff` | TOWN overlay cache |
| `$c000-$cfff` | DEATH overlay cache |
| `$d000-$dfff` | post-boot runtime I/O-visible gap; never runtime cache/data RAM |
| `$e000-$efff` | DUNGEON overlay cache |
| `$f000-$feff` | top common RAM; shared, not cache-safe |

The staged PRG payload begins at `$1c01`, but the page copier physically reads
and scrubs Bank 1 `$1c00-$feff`, including RAM under
`$d000-$dfff` while a no-I/O mode is selected. This is the sole documented
exception to the post-boot runtime ownership table. The copy-to-Bank-0 process
scrubs staged pages. Cache validity cannot be assumed until the relevant cache
has been repopulated and marked valid.

Important Bank 0 ownership includes floor items at `$1a00-$1aff`, runtime
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
