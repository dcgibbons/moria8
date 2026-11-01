# Commander X16 Memory Contract

Placement and banking source of truth for the Commander X16 port (`platforms/cx16/`).
Enforced at link time by `.assert` guards in `platforms/cx16/memory.s` and
`platforms/cx16/main.s`, and at build time by `platforms/cx16/check_memory_contract.py`.

## 1. Fixed Low RAM (`$0000-$9FFF`)

The Commander X16 provides 38.6 KB of unbanked low RAM (`$0801-$9EFF`) plus
`$0400-$07FF` (1,024 bytes unused by the KERNAL because VERA text lives in
VRAM `$1B000`). Switching the active RAM bank via ZP `$00` affects **only**
`$A000-$BFFF`; `$0000-$9EFF` is always visible.

| Address Range | Size | Owner | Notes |
| --- | ---: | --- | --- |
| `$0000` | 1 B | `CX16_RAM_BANK_REG` | Active 8 KB RAM bank at `$A000-$BFFF` (`0..63`) |
| `$0001` | 1 B | `CX16_ROM_BANK_REG` | Active 16 KB ROM bank at `$C000-$FFFF` (`0` = KERNAL) |
| `$0002-$008F` | 142 B | Shared Core ZP (`core/zeropage.s`) | `$02-$7F` is application ZP; `$80-$8F` is saved/restored around KERNAL file I/O (`save_zp`/`restore_zp`) |
| `$0090-$00FF` | 112 B | CX16 KERNAL ZP | Reserved for KERNAL routines |
| `$0100-$01FF` | 256 B | Hardware Stack | Always unbanked |
| `$0200-$03FF` | 512 B | KERNAL Vectors & System Scratch | Reserved for CX16 KERNAL; boot chains the `keyhdl` vector (`$032E`) to `cx16_key_event` (`platforms/cx16/input.s`), which tracks held keys for `input_wait_release` |
| `$0400-$04FF` | 256 B | `FLOOR_ITEM_BASE` | Active level floor-item table |
| `$0500-$05FF` | 256 B | `CREATURE_BASE` | Runtime creature/RLE/high-score scratch |
| `$0600-$06FF` | 256 B | `PLATFORM_HD_DECODE_BUF_BASE` / `DUNGEON_GEN_DOOR_SCAN_BASE` | Shared Huffman decode & dungeon-gen door-scan scratch |
| `$0700-$07FF` | 256 B | `CX16_ROW_STAGE_BASE` (`rv_row_map_buf`, `rv_row_color_buf`) | Shared VERA row staging & page-burst file I/O staging buffer |
| `$0801-$9AFF` | 37,631 B | Unified Resident + Play Image (`MORIA8.PRG`) | BASIC stub at `$0801`, entry at `$080D`, all resident + gameplay modules |
| `$9B00-$9EFF` | 1,024 B | `PLATFORM_TIER_NAME_POOL_BASE` | Active monster tier name pool (core raw-addressed) |
| `$9F00-$9FFF` | 256 B | Hardware I/O (`VIA1`/`VIA2` `$9F00-$9F1F`, `VERA` `$9F20-$9F3F`) | Forbidden to code/data |

## 2. Banked RAM Window (`$A000-$BFFF`, 8 KB × 64 Banks)

Each 8 KB RAM bank (`$A000-$BFFF`) has a dedicated, non-overlapping owner:

| RAM Bank | Virtual Address | Payload / File | Owner & Lifecycle |
| ---: | --- | --- | --- |
| `0` | N/A | System / KERNAL `KVARSB0` | Reserved for CX16 KERNAL (keyboard count `$A80A`, etc.); never overwritten |
| `1` | `$2000-$3FFF` | Live Map Low Half (8,192 B) | First 8,192 B of the 198×66 dungeon map (`MAP_BASE = $2000`) |
| `2` | `$4000-$530B` | Live Map High Half (4,876 B) | Remaining 4,876 B of the 198×66 dungeon map (`MAP_END = $530B`) |
| `3` | `$6000-$7FFF` | `CX16.AUXDATA` (`Cx16AuxData`) | Preloaded at boot: item name streams, `it_unknown_idx`, store inventory/runtime, recall arrays, spell tables/names, ego suffix slots |
| `4` | `$8000-$9FFF` | `CX16.HUFFDATA` (`Cx16HuffData`) | Preloaded at boot: Huffman tree and compressed string corpus |
| `5` | `$A000-$BFFF` | `MONSTER.DB.1` | Preloaded at boot: Tier 1 monster database |
| `6` | `$A000-$BFFF` | `MONSTER.DB.2` | Preloaded at boot: Tier 2 monster database |
| `7` | `$A000-$BFFF` | `MONSTER.DB.3` | Preloaded at boot: Tier 3 monster database |
| `8` | `$A000-$BFFF` | `MONSTER.DB.4` | Preloaded at boot: Tier 4 monster database |
| `9` | `$A000-$BFFF` | `OVL.START` (`OVL_STARTUP = 1`) | Preloaded at boot: character creation & item ID init |
| `10` | `$A000-$BFFF` | `OVL.TOWN` (`OVL_TOWN = 2`) | Preloaded at boot: town stores & home UI |
| `11` | `$A000-$BFFF` | `OVL.DEATH` (`OVL_DEATH = 3`) | Preloaded at boot: death/retirement/score & heavy area spells |
| `12` | `$A000-$BFFF` | `OVL.GEN` (`OVL_DUNGEON_GEN = 4`) | Preloaded at boot: town & dungeon generator + special rooms |
| `13` | `$A000-$BFFF` | `OVL.HELP` (`OVL_HELP = 5`) | Preloaded at boot: 80-col help, inventory, and equipment screens |
| `14` | `$A000-$BFFF` | `OVL.UI` (`OVL_UI = 6`) | Preloaded at boot: character sheet & symbol identify UI |
| `15` | `$A000-$BFFF` | `OVL.ITEMS` (`OVL_ITEMS = 7`) | Preloaded at boot: item actions, wear/takeoff/eat/quaff, bash/disarm/tunnel |
| `16` | `$A000-$BFFF` | `OVL.SPELL` (`OVL_SPELL = 8`) | Preloaded at boot: spell/prayer selection, execution, and level-up |
| `17` | `$A000-$BFFF` | `OVL.MODAL` (`OVL_MODAL_MISC = 9`) | Preloaded at boot: monster recall, wizard UI, royal screen, look |
| `18` | `$A000-$BFFF` | `OVL.CHEST` (`OVL_CHEST = 10`) | Preloaded at boot: chest open/disarm/bash, door jam/pick, store restock |
| `19` | `$A000-$BFFF` | `OVL.STORAGE` (`OVL_STORAGE = 11`) | Preloaded at boot: shared save/load engine & slot menu |
| `20` | `$A000-$BFFF` | `OVL.TITLE` (`OVL_TITLE = 12`) | Preloaded at boot: title screen renderer & system info |
| `21` | `$A000-$BFFF` | `TITLE` | Preloaded at boot: title screen artwork stream |

## 3. Virtual-to-Banked Address Translation (`$2000-$9FFF`)

Every virtual address `V = zp_ptr + Y` in `$2000-$9FFF` maps deterministically
to a 8 KB RAM bank and `$A000-$BFFF` window address:

* Effective 16-bit address: `eff_addr = zp_ptr + Y`, with `eff_hi = eff_addr >> 8` and `eff_lo = eff_addr & $FF`.
* Target RAM bank: `bank = eff_hi >> 5` (`1` for `$20-$3F`, `2` for `$40-$5F`, `3` for `$60-$7F`, `4` for `$80-$9F`).
* Window address inside `$A000-$BFFF`: `win_addr = (((eff_hi & $1F) | $A0) << 8) | eff_lo`.

Because `zp_ptr + Y` is resolved to a 16-bit effective address before computing
`bank` and `win_addr`, indexed accesses `(zp_ptr0),y` and `(zp_ptr1),y` never
cross `$BFFF` into `$C000` ROM even when a map row straddles the `$3FFF/$4000`
boundary between Bank 1 and Bank 2.

All `mmu_safe_map_read_ptr0/1` and `mmu_safe_map_write_ptr0/1` calls execute in
fixed low RAM, save and restore `CX16_RAM_BANK_REG` (`$00`), and preserve `X`,
`Y`, and carry (`C`), so code executing inside any overlay bank (`9..20`) can
freely read and write the Map, `Cx16AuxData`, and `Cx16HuffData`.

## 4. Verification Gates

* Static memory contract self-test: `make testcx16-memory-contract-selftest`
* Static linked-symbol & PRG extent gate: `make testcx16-memory-contract`
* Runtime TestBench suite: `make testcx16-runtime` (21 scenarios in `platforms/cx16/harness_smoke.py`)
