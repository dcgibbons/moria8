# Commander X16 Cartridge Port (`CX16_CARTRIDGE`)

## Summary

`CX16_CARTRIDGE` packages Moria8 for the Commander X16 into a 128 KB (8 x 16 KB
banks, ROM Banks `32..39`) cartridge image without changing any disk-build bytes
in `build/cx16/`:

- Emulator cartridge image: `build/moria8-cx16.crt` (`131,552` bytes = 480-byte
  `CX16 CARTRIDGE` v01.00 header with `bank_info[0..7] = 1` ROM, `bank_info[8..223] = 0`,
  followed by 128 KB payload).
- Raw NOR-flash image: `build/cx16-cart/moria8-cx16.bin` (`131,072` bytes).
- Manifest: `build/cx16-cart/moria8-cx16.json` (`101,027` payload bytes used,
  `30,045` bytes free).

## Hardware Banking & No-Bounce Architecture

On Commander X16, `$00` selects the 8 KB RAM bank (`0..63`) at `$A000-$BFFF` and
`$01` selects the 16 KB ROM bank (`0` = KERNAL, `32+` = Cartridge ROM) at
`$C000-$FFFF`. Because `$C000-$FFFF` never overlaps fixed low RAM (`$0000-$9EFF`)
or banked RAM (`$A000-$BFFF`), cartridge copies run straight from ROM to their
destination bank with **no bounce buffer**.

### Cold Boot (`platforms/cx16/cartridge_boot.s`, Bank 32 `$C000-$C0B4`)

1. `$C000-$C003` holds `"CX16"` so `x16-rom` `boot_cartridge` auto-starts `$C004`
   (`boot_cold_start`) with `I=1`.
2. `boot_cold_start` sets `cld`, resets stack (`ldx #$ff; txs`), sets `$00=0`, and
   copies a self-contained copier stub (`boot_ram_stub`) into `$0400-$04FF`
   (`CART_COPY_STUB_ADDR`, pre-init `FLOOR_ITEM_BASE`).
3. `boot_ram_stub` reads descriptor `0` (`MORIA8.PRG`) from `$C100`, streams all
   `37,116` bytes across ROM Bank boundaries (`$FFFF -> $C000`, `inc $01`) into
   `$0801..$98FC`, restores `$00=0` and `$01=0` (KERNAL Bank 0), clears any
   keys buffered during `boot_cartridge`'s Shift-check window (`stz $A80A`),
   executes `cli` so VERA VSYNC / keyboard IRQs run cleanly, and jumps to
   `entry_bootstrap` (`$080D`).
4. Under `x16emu` (`$9FBE/$9FBF == "16"`) when a harness primes `$07FC-$07FF` with
   `"M8TB"`, `boot_copy_done` clears the magic and jumps to `$FFFD` (`RDY`) so
   the TestBench harness can verify RAM checksums before entering `entry_bootstrap`.

### Resident Loader & Asset Map (`platforms/cx16/cartridge_copy.s`, `cartridge_contract.s`)

Bank 32 `$C100-$C19F` holds 20 x 8-byte descriptors (`bank`, `rom_lo`, `rom_hi`,
`dest_lo`, `dest_hi`, `ram_bank`, `size_lo`, `size_hi`):

| ID | Asset | ROM Location | Target Bank | Dest | Size |
| --- | --- | --- | --- | --- | --- |
| 0 | `MORIA8.PRG` | Bank 32 `$C200` | RAM Bank 0 | `$0801` | `37,116` |
| 1 | `CX16.AUXDATA` | Bank 34 `$D2FC` | RAM Bank 3 | `$A000` | `5,120` |
| 2 | `CX16.HUFFDATA` | Bank 34 `$E6FC` | RAM Bank 4 | `$A000` | `7,159` |
| 3 | `OVL.START` | Bank 35 `$C2F3` | RAM Bank 9 | `$A000` | `4,213` |
| 4 | `OVL.TOWN` | Bank 35 `$D368` | RAM Bank 10 | `$A000` | `5,208` |
| 5 | `OVL.DEATH` | Bank 35 `$E7C0` | RAM Bank 11 | `$A000` | `3,345` |
| 6 | `OVL.GEN` | Bank 35 `$F4D1` | RAM Bank 12 | `$A000` | `4,787` |
| 7 | `OVL.HELP` | Bank 36 `$C784` | RAM Bank 13 | `$A000` | `2,273` |
| 8 | `OVL.UI` | Bank 36 `$D065` | RAM Bank 14 | `$A000` | `2,483` |
| 9 | `OVL.ITEMS` | Bank 36 `$DA18` | RAM Bank 15 | `$A000` | `5,605` |
| 10 | `OVL.SPELL` | Bank 36 `$EFFD` | RAM Bank 16 | `$A000` | `5,842` |
| 11 | `OVL.MODAL` | Bank 37 `$C6CF` | RAM Bank 17 | `$A000` | `2,847` |
| 12 | `OVL.CHEST` | Bank 37 `$D1EE` | RAM Bank 18 | `$A000` | `2,520` |
| 13 | `OVL.STORAGE` | Bank 37 `$DBC6` | RAM Bank 19 | `$A000` | `3,304` |
| 14 | `OVL.TITLE` | Bank 37 `$E8AE` | RAM Bank 20 | `$A000` | `325` |
| 15 | `TITLE` | Bank 37 `$E9F3` | RAM Bank 21 | `$A000` | `622` |
| 16 | `MONSTER.CAT` | Bank 37 `$EC61` | RAM Bank 22 | `$A000` | `5,976` |
| 17 | `LEGALUI` | Bank 38 `$C3B9` | RAM Bank 23 | `$A000` | `927` |
| 18 | `LICENSE` | Bank 38 `$C758` | `None` (`$FF`) | `$0000` | `344` |
| 19 | `SOURCE-OFFER` | Bank 38 `$C8B0` | `None` (`$FF`) | `$0000` | `499` |

Notes from implementation:
- Overlay IDs in `platforms/commodore/common/overlay.s` (`OVL_STARTUP=1..OVL_CHEST=10`)
  and `platforms/cx16/main.s` (`OVL_STORAGE=11`, `OVL_TITLE=12`) map to RAM Banks
  `9..20` in `CX16_OVERLAY_TABLE_COUNT` order (`platforms/cx16/storage_kernal.s`).
  `tools/check_cx16_cart.py` enforces this exact ID-to-RAM-bank layout.
- `cart_load_asset`, `cart_read`, and `cart_load_prg` save and restore `$00`, `$01`,
  and `P`, use zero ZP bytes, and leave `cx16_preload_banks` free of HostFS/KERNAL
  program loads.
- `platforms/cx16/legal_stream.s` streams `LICENSE` and `SOURCE-OFFER` in
  128-byte chunks via `cart_read` (`cart_is_record = 2`).
- Saves (`"THE.GAME"`..`"THE.GAME4"`) and `HALL.OF.FAME` remain on HostFS/SD Drive 8–11 and
  are binary-compatible with `build/cx16/MORIA8.PRG`.

## `x16emu -testbench` Cold-Boot Finding

In `x16emu -testbench`, VERA VBLANK interrupts do not advance `RDTIM`, so
`x16-rom`'s 60-jiffy `boot_cartridge` wait stalls before `RDY` when `$C000..$C003`
contains `"CX16"`. `platforms/cx16/test_cartridge.py` therefore splits
verification into:
1. Unmodified autonomous `-cart` and `-cartbin` cold-boot tests without
   `-testbench`, verifying title banner and menu pixels via `-gif` capture under an
   empty `-fsroot`.
2. Interactive `-testbench` runs (`CartBench`) using a testbench-only copy with
   byte `$C000 = $00` + a 3-byte `$0801: rts` stub to reach `RDY`, priming `"M8TB"`
   at `$07FC-$07FF`, and invoking `RUN C004` (`boot_cold_start`) directly.

## Verification Gates Observed (2026-11-13)

- `python3 tools/check_cx16_cart.py --selftest`: PASS
- `python3 platforms/cx16/test_cartridge.py --selftest`: PASS
- `make testcx16-memory-contract-selftest`: PASS
- `make testcx16-memory-contract`: PASS (`19 asserts 0 failures` on `build/cx16` and `build/cx16-cart`, `check_cx16_cart.py: PASS`)
- `make check-hal-boundaries` & `make check-6502-lint`: PASS (`0 error(s)`)
- `make testcx16-cartridge`: PASS (autonomous `-cart` / `-cartbin` GIF boot, autonomous non-testbench/non-warp `-cart` live 60 Hz VSYNC IRQ / `RDTIM` / `KEYHDL` / VERA PSG WAV audio playback and silencing + keyboard flow (`P=$32`, `snd_timer=12->0`, `wav_peak=4088`), `CartBench` handoff `I=0` & `$A80A` flush, `KEYHDL` chain, preloaded-bank Fletcher-16, `cart_read` edge cases, empty-fsroot missing-save `L)oad`, Title/Gameplay legal viewer reaching EOF with `legal_eof = $40`, town/DL1/DL16/DL50 monster catalog, empty `-fsroot` isolation, bidirectional `"THE.GAME"` interchange with disk `MORIA8.PRG`); `make testcx16`: PASS
- `make testcx16`: PASS (memory contract + all 25 `harness_smoke.py` disk scenarios + `test-cartridge`)
