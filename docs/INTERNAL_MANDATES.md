# Internal Mandates

This file preserves durable engineering and hardware invariants for Moria8. It
is intentionally limited to rules that protect the source tree and runtime
architecture.

## Repository Hygiene

- Do not commit credentials, secrets, private environment files, generated
  build outputs, VICE snapshots, downloaded toolchains, or monitor logs.
- Do not stage or commit changes unless explicitly requested.
- Keep public documentation free of local machine paths and private process
  notes.

## User-Facing Text

Player-visible strings are product data. Do not shorten, rename, truncate, or
otherwise degrade prompts, menu labels, spell feedback, disk filenames, loading
lists, status messages, or error text merely to recover bytes.

When memory pressure appears, first recover space from ownership, overlays,
deduplication, dead code, or data layout. Only change player text for a real
product reason, and verify the rendered path on the affected target.

## Memory Boundaries

- C64 main segment must end below `$C000`.
- C128 main/default segment must end below its asserted runtime ceiling.
- Apple IIe resident ends below `$7C00`, play slot spans `$7C00-$9FFF`, and
  overlays fit in `$A400-$B9FF` (`docs/APPLE2_MEMORY_POLICY.md`).
- Commander X16 unified resident/play ends at or below `$9AFF`, tier-name pool
  spans `$9B00-$9EFF`, `$9F00-$9FFF` is the VERA/VIA I/O hole, and banked
  overlays fit in `$A000-$BFFF` (`docs/CX16_MEMORY_CONTRACT.md`).
- Atari 8-bit low resident banking/SIO/130XE/interrupt helpers end at or below
  `$4000`, `Default` resident ends at or below `$C100`, `MAP_BASE` spans
  `$C100-$CFFF` (`3,840` B), `$D000-$D7FF` is the immovable GTIA/POKEY/PIA/ANTIC
  I/O hole, overlays fit in `$E000-$EFFF`, and `RuntimeBanked` spans
  `$F000-$FFF9` (`docs/ATARI8_MEMORY_CONTRACT.md`).
- BBC Master 128 low resident banking/blitter/MOS helpers end at or below
  `$3000`, `Default` resident ends at or below `$8000`, 20 KB Shadow RAM `LYNNE`
  (`$3000-$7FFF`) holds the font, scan scratch, `beeb_char_shadow`, and Mode 0
  bitmap, 4 KB Private RAM `ANDY` (`$8000-$8FFF`) holds `BeebHuffData`, and
  Sideways RAM Banks 4–7 (`$8000-$BFFF`) host `BeebPlaySlot`,
  `PLATFORM_TIER_NAME_POOL_BASE`, the `$A800-$BFFF` overlay/tier window,
  `MAP_BASE`, `BeebAuxData`, and cached overlays (`docs/BBCMASTER_MEMORY_CONTRACT.md`).
- CP/M 2.2 Z80 requires a 52 KB minimum TPA (`BDOS_MIN_TOP = 0xD100`): resident
  `MORIA8.COM` spans `0x0100-0x55FF`, 19 streamed overlays share the `0x5600-0x69FF`
  window (`5,120` B), resident BSS occupies `0x6A00-0x8BFF` (`z80_state` at
  `0x6A00-0x6A3F`), the 512 B stack spans `0x8C00-0x8DFF`, shadows + `MAP_BASE`
  (`0x9D00-0xD00B`, `198x66` = `13,068` B) overwrite CCP, and the FCB pool +
  `cpm_dma_buf` (`0xD00C-0xD0FF`) sit strictly below `0xD100` (`docs/CPM_MEMORY_CONTRACT.md`).
- The C64 map owns `$C000-$CEFF`; the C64 floor-item table owns `$CF00-$CFFF`.
- `$D000-$DFFF` is the Commodore I/O hole when I/O is visible and must not
  receive normal executable code or ordinary runtime payload data.
- Banked payloads must end below CPU vectors.
- Each Commodore overlay segment must fit in `$E000-$EFFF`.
- Test code entered directly through BASIC must start below `$A000`, or use a
  bootstrap trampoline that banks out BASIC ROM first.

Placement is decided with the feature, not when a segment runs out. A module
whose placement differs by port, or that runs in an overlay or banked segment,
states in its header: its **owner** on each port (segment or overlay), its
**lifetime** (one call, one cast, one level, the session; boot-only code that a
restart runs again is not boot-only), and its **callers** that can arrive with
another overlay loaded, and how that entry gets its owner back. Where a fact can
be checked, an `.assert` (or Z80 `ASSERT`) beside the placement checks it
(e.g. a routine called from another overlay lies outside the `$E000` or
`0x5600–0x69FF` overlay window). Moving a module updates its header, the assert,
and the port's memory contract row. Code whose only callers live in an overlay
belongs in that overlay where it fits, on unshipped ports too: don't leave a
misplacement for later. Keep three results apart: removing code (smaller
product), moving it (pressure redistributed), and shortening a copy (less
transfer, often no space freed).

After import reordering, segment movement, banking changes, or runtime payload
layout changes, rebuild and inspect the assembler memory map and `.print` /
`.lst` output. Existing boundary `.assert` and Z80 `ASSERT` statements are part
of the contract; fix the layout when they fail.

## Zero Page And KERNAL

- `$02-$8F` is game-owned only under the project's documented caller-save
  discipline.
- KERNAL routines clobber some low zero-page locations, including LOAD/SAVE and
  OPEN scratch locations. Long-lived game state must not rely on those bytes
  across KERNAL calls without save/restore.
- `$90-$FF` is KERNAL-volatile unless a specific platform file proves otherwise.

## C128 Banking

- Do not modify `$FF00` or processor port banking state without an atomic
  interrupt-safe sequence or a context-aware restore.
- Use established KERNAL entry/exit helpers for KERNAL calls.
- Keep `$D506` common RAM configuration at the documented 4 KB bottom/top common
  model unless the architecture and all assertions are redesigned together.
- Hardware vectors must point to common RAM or a validated vector bridge.
- Bank 1 ownership must follow `platforms/commodore/c128/memory128.s`;
  unassigned RAM is not free until an ownership entry and overlap assertions are
  added.
- `$1000-$3FFF` is bank-private in the shipping C128 runtime.
- `$D000-$DFFF` is not high RAM to borrow while I/O is visible.

## C128 Runtime-Loaded Code

For copied, disk-loaded, banked, recopied, or trampolined C128 code, verify:

1. linked symbol address
2. PRG load header
3. destination bank at load time
4. visible bank at execution time
5. staged source-span survival

Moving crash addresses usually indicate an ownership or visibility mismatch.
Re-check the full contract before patching local logic near the newest crash.

## Shared Code

- Shared entity data should remain struct-of-arrays.
- Use the existing math library for 16-bit arithmetic.
- Use the project RNG rather than ad hoc hardware reads.
- Shared `platforms/commodore/common/` changes that affect
  platform-conditional code must be verified on C64, C128, and Plus/4 where the
  code is included.
- Shared `core/6502/` and `platforms/shared/` changes must be verified on all
  seven 6502/65C02 platforms (C64, C128, Plus/4, Apple IIe, Commander X16,
  Atari 8-bit, and BBC Master 128), and gameplay/catalog/formula changes must
  maintain `core/6502/` ↔ `core/z80/` cross-ISA parity on CP/M 2.2 (Z80).

## Verification

- Bug fixes should be backed by a failing reproduction or test where practical.
- Reported failing commands become the active gate until that exact command
  passes.
- For C128 work, prefer `make test128-fast` for unit iteration and
  `make test128-fast-smoke` for fast runtime smoke coverage. Use `make test128`
  before signing off broad banking, loader, overlay, or MMU changes.
- Headless VICE tests should use warp mode and should not rely on timeouts over
  30 seconds.

## Commodore Storage And KERNAL I/O

Changes touching `core/6502/ui_disk_setup.s`, `platforms/shared/save.s`,
`platforms/commodore/common/disk_*.s`, `save_slot_menu.s`, or
`platforms/commodore/*/hal/storage*.s` must verify all three invariants:

1. **Real emulator failure-path coverage:** Never treat mocked unit tests or
   host `c1541` image checks (`disk_media_probe.py`) as proof of hardware/KERNAL
   error handling. On C128/Plus/4 KERNALs, empty-name `OPEN` does not probe the
   bus until `CHKIN`+`READST`. On stock C64 KERNAL, empty-name `OPEN` also
   skips `STA $90` while `CHKIN`->`TKSA` (`$EDC7`) hangs forever at `$EDD6` on an
   absent device unless `$90` (`KERNAL_STATUS`) is cleared and `CHKOUT`
   (`LISTEN`+`SECOND`) probes presence first.
2. **Producer-to-UI sentinel parity:** Trace error sentinels (`$00`, `$FF`,
   `READST`, truncated/non-digit DOS bytes) from status readers into screen RAM
   (`uds_show_init_detail`, `save_append_disk_detail_*`) so non-digit sentinels
   are never printed as screen codes.
3. **Explicit device binding:** `hal_storage_read_command_status` binds
   `save_device` directly; non-save callers (such as `program_device` in
   `legal.s` or `disk_prompt_device` in `hal_storage_init_selected_drive`) must
   pass the target device explicitly via `_x` entrypoints rather than relying on
   a shared `disk_prompt_device` global. Also run the targeted
   `make playtest-disk` fault scenarios (`absent_save_drive`, `empty_drive`,
   `status_lost_save`, etc.) when changing Commodore storage or setup UI code.

## Release Compliance Matrix

Every shipping disk image, archive, container, and cartridge must include
`data/LICENSE` and `data/SOURCE-OFFER` (viewable via Title `A` (`About`) and
Help `L`):

| Shipping Target | Embedded Names / Assets | Format / EOL |
| --- | --- | --- |
| Commodore disk (`c64`, `c128`, `plus4`) | SEQ files `license,s`, `source-offer,s` | `LF -> CR` |
| Apple IIe disk | ProDOS TXT files `LICENSE`, `SOURCE.OFFER` | `LF -> CR` |
| Commander X16 `.zip` | `LICENSE`, `SOURCE-OFFER` | `LF -> CR` |
| Atari 8-bit `.atr` | DOS 2.5 files `LICENSE.TXT`, `SRCOFFER.TXT` | `LF -> $9B` (ATASCII) |
| BBC Master 128 `.ssd` | DFS files `LICENSE`, `SRCOFFR` | `LF -> CR` |
| CP/M `.zip` (`build/moria8-cpm.zip`) | `LICENSE`, `SOURCE-OFFER`, `README.TXT` | `LF -> CRLF` |
| CP/M `.dsk`/`.d71` (`kaypro2`, `kaypro4`, `c128`) | `LICENSE.TXT`, `SRCOFFR.TXT` | `LF -> CRLF` + `0x1A` EOF, 128 B padded |
| CP/M `MORIA8.DAT` (`'M8CP'`) | `DAT_ID_LICENSE`, `DAT_ID_SRCOFFR` | Embedded in container |
| Cartridges (`c64`, `c128`, `plus4`, `cx16`, `atari8`) | Embedded ROM assets | Raw / NUL-padded ROM |

## Platform Harnesses & External Toolchains

- **Port isolation (`tools/isolated.sh`):** Root-Makefile emulator test targets
  and playtest runs execute in a private network namespace (`ISOLATE=auto|1|0`,
  default `auto`) so concurrent runs do not collide on monitor ports. Prefix
  direct `make -C platforms/...` or harness runs with `tools/isolated.sh` when
  other agents may be testing.
- **Toolchains (`tools/` defaults):** Kick Assembler installs into
  `tools/kickass/` unless `KICKASS` is set; `sjasmplus`, `RunCPM`, and
  `ctools`/`cformat` install/build into `tools/` unless `SJASMPLUS`, `RUNCPM`,
  `CTOOLS`, and `CFORMAT` are supplied. Initial downloads need network outside
  sandboxed execution when absent from `tools/`.
- **Commodore runtime tests:** A new C64 test hang after a layout change is
  usually a memory overlap—inspect the assembler map and asserts first. Tests
  with `test_start >= $A000` must use a bootstrap stub below BASIC ROM to bank
  RAM visible first.
- **Non-Commodore harnesses & caller-supplied ROM env vars (`?=`):**
  - Apple IIe (`platforms/apple2/harness_smoke.py`): headless MAME `apple2ee`
    (requires `A2ROMS` / `--rompath`; 1 scenario per invocation).
  - Commander X16 (`platforms/cx16/harness_smoke.py`): headless `x16emu
    -testbench` (requires `X16EMU`, `X16ROM`).
  - Atari 8-bit (`platforms/atari8/harness_smoke.py`): headless MAME `a800xl`
    and `a130xe` (requires `ATARI8ROMS`).
  - BBC Master 128 (`platforms/bbcmaster/harness_smoke.py`): headless MAME
    `bbcm` (requires `BBCMROMS`).
  - CP/M 2.2 Z80 (`platforms/z80/cpm/harness_smoke.py`): drives
    `tools/cpm_runner` and `RunCPM` over stdio (0 sockets; `make diskcpm` uses
    `tools/make_cpm_disk.py` + `tools/ctools/`).
