# Moria8 Manual

Moria8 is an assembly adaptation of the classic Moria roguelike for eight 8-bit
platforms: **Commodore 64**, **Commodore 128**, **Commodore Plus/4**, **Apple
IIe** (128K), **Commander X16**, **Atari 8-bit** (`800XL`/`65XE`/`130XE`),
**Acorn BBC Master 128**, and **CP/M 2.2 (Z80)**.
You create one adventurer, prepare in town, descend through the dungeon, grow
stronger, and try to defeat the Balrog.

This manual covers all eight current platforms. Moria8 follows VMS Moria and Umoria closely in spirit, with two
hardware-scaled map geometries sharing the same core rules:

- **40-column ports (`80x48` active map):** Commodore 64, Commodore Plus/4, and
  Atari 8-bit.
- **80-column ports (`198x66` active map):** Commodore 128, Apple IIe, Commander
  X16, Acorn BBC Master 128, and CP/M 2.2 (Z80).

## Starting The Game

Choose the cartridge or disk/archive release for your machine:

- **Commodore 64:** `moria8-c64.crt` (cartridge, recommended for cartridge
  adapters and C64 Ultimate) or `moria8-c64.d64` (1541 disk). Disk builds use
  REU caching automatically when an REU is present.
- **Commodore 128:** `moria8-c128.crt` (Magic Desk 128 cartridge) or
  `moria8-c128.d64`, `moria8-c128.d71`, or `moria8-c128.d81` (boots in native
  80-column VDC mode; caches code/data in Bank 1 and VDC RAM).
- **Commodore Plus/4:** `moria8-plus4.crt` (Magic Cart cartridge) or
  `moria8-plus4.d64` (1541-compatible disk).
- **Apple IIe (128K, ProDOS):** `moria8-apple2.po` (also runs on Apple IIc and
  Apple IIgs; caches hot overlays and catalogs in auxiliary / Language Card RAM
  and streams cold overlays from ProDOS on demand).
- **Commander X16:** `moria8-cx16.zip` (extract into a dedicated SD card
  subfolder such as `MORIA8/`, then `DOS"CD:MORIA8"` and `BOOT` to launch
  `AUTOBOOT.X16`, or `LOAD"MORIA8.PRG"` / `RUN` — do not extract to the SD root
  if you already have an `AUTOBOOT.X16` launcher; also supports uploading the
  `.zip` directly to the CX16 WebEmulator via `manifest.json`, or passing
  `-fsroot <dir>` in `x16emu` and running `MORIA8.PRG`; preloads overlays and
  catalogs into banked HiRAM at boot) or `moria8-cx16.crt` (128 KB cartridge ROM
  for `x16emu -cart` or hardware ROM cards).
- **Atari 8-bit (`800XL`/`65XE`/`130XE`):** `moria8-atari8.car` (AtariMax 128
  KB cartridge) or `moria8-atari8.atr` (DOS 2.5 Enhanced Density disk). A
  `130XE` automatically caches overlays and catalogs in extended RAM at boot;
  stock `64 KB` `800XL`/`65XE` machines stream from `D1:` on demand.
- **Acorn BBC Master 128:** `moria8-bbcmaster.ssd` (Acorn DFS 80-track disk;
  boot via `SHIFT+BREAK` or `*EXEC !BOOT`, using Mode 0 Shadow RAM `LYNNE`,
  `ANDY`, and Sideways RAM).
- **CP/M 2.2 (Z80):** Built by `make diskcpm` as
  `moria8-cpm.zip`, `moria8-cpm-kaypro2.dsk`, `moria8-cpm-kaypro4.dsk`, and
  `moria8-cpm-c128.d71` (run with `make runcpm` or on Z80 CP/M 2.2 / CP/M Plus
  with `>= 52 KB` TPA, BDOS base `>= 0xD100`). Keep `MORIA8.COM` and
  `MORIA8.DAT` on the same launch drive/user area. Launch with `MORIA8`
  (ADM-3A monochrome default `/A`), `MORIA8 /V` (VT100/ANSI 16-color SGR), or
  `MORIA8 /M` (VT100/ANSI monochrome), plus an optional `[A-P]:` save-drive
  override (e.g., `MORIA8 /V B:`).

On the title screen, choose:

- `N` (`N)ew`) to create a new character.
- `L` (`L)oad`) to resume a saved character from slots `1`–`4`.
- `D` (`D)isk Setup`) to select and initialize save media.
- `A` (`A)bout`) to open the About menu (`1` License, `2` Source Offer, `3`
  System Info).
- *(CP/M 2.2 Z80 only)* `M` cycles terminal output mode (`[ADM-3A]` → `[Color]`
  → `[Mono]`), and `Q` / `ESC` exits cleanly to CP/M.

### Save Media, Save Format V2 (`$22`), And Compatibility

On the floppy-swap 6502 ports (Commodore, Apple IIe, Atari 8-bit, BBC Master
128), program media and save media are deliberately separated and Moria8 refuses
to write saves or markers onto a program disk; on HostFS/SD and CP/M targets,
saves can share the launch drive or target another mounted drive. All five
cartridge editions load game code, overlays, and catalogs directly from
read-only ROM with zero program disk swaps, but still require writable save
storage configured through `D)isk Setup`:

- **Commodore / Commander X16:** Supports IEC/HostFS devices `8`–`11`. Moria8
  writes `MORIA8.ID`, `THE.GAME`–`THE.GAME4`, and `HALL.OF.FAME`
  (`P4.HALL.FAME` on Plus/4). On Commander X16, HostFS/SD defaults to device `8`.
- **Apple IIe:** Supports ProDOS volumes across drives (two-drive or
  single-drive swap), writing `MORIA8.ID`, `THE.GAME`–`THE.GAME4`, and
  `HALL.OF.FAME`.
- **Atari 8-bit:** Supports drives `D1:`–`D4:` using DOS 2.5 `.atr` save disks
  (`MORIA8.ID`, `SAVE0.SAV`–`SAVE3.SAV`, and `HISCORE.DAT`).
- **Acorn BBC Master 128:** Supports DFS drives `:0`–`:3` (`MORIAID`,
  `SAVE0`–`SAVE3`, and `HISCORE`).
- **CP/M 2.2 (Z80):** Supports drives `A:`–`P:` (defaulting to the active launch
  drive, or selectable via `D)isk Setup` `1) Same as program` / `2) Pick save
  drive` or CLI `[A-P]:`; no `MORIA8.ID` marker required), writing
  `SAVE0.SAV`–`SAVE3.SAV` and `HISCORE.DAT` via safe `.TMP` atomic rename.

Current builds use **Save Format V2** (`SAVE_VERSION = $22`) across all eight
active platforms:

- **Pre-V2 saves are rejected:** Older saves (`< $22`) and incompatible future
  versions (`> $22`) are rejected cleanly with `Unsupported save.` without
  modifying your session or disk. Start a new character on a fresh or
  reinitialized save slot.
- **Disk and cartridge saves are interchangeable within a platform:** For
  example, saves created on `moria8-c64.d64` load on `moria8-c64.crt` (and vice
  versa); the same applies to C128, Plus/4, Commander X16, and Atari 8-bit.
- **Cross-geometry saves (`80x48` vs. `198x66`) are incompatible:** Saves from
  40-column `80x48` ports (**C64, Plus/4, Atari 8-bit**, `7,858` bytes) cannot
  be loaded on 80-column `198x66` ports (**C128, Apple IIe, Commander X16, BBC
  Master 128, CP/M 2.2 Z80**, `17,164` bytes; `135` CP/M 128 B records) — or
  vice versa. In particular, C64 and C128
  share the `"MORIA01"` Save V2 header and Commodore filenames, so attempting to
  load a C64 save on a C128 (or a C128 save on a C64) will pass the header check
  and fail mid-stream with `Save file corrupt!`. Always keep separate save disks
  for 40-column and 80-column machines. (Plus/4 uses its own `"MORIA+4"` header
  and rejects other ports immediately with `Unsupported save.`.)

On first start, create a character by choosing race, class, sex, and rolled
stats. The game then generates a social background, starting gold, hit points,
mana where applicable, and starting equipment.

## Character Basics

Moria8 uses the classic six stats:

| Stat | Main Uses |
| ---- | --------- |
| STR | Melee damage, heavy weapons, digging, bashing, carrying weight. |
| INT | Mage spell learning, mage mana, devices, disarming. |
| WIS | Priest prayer learning, priest mana, saving throw. |
| DEX | Hitting, dodging, multiple blows, and disarming. |
| CON | Hit points and bodily resistance. |
| CHR | Store prices and starting money. |

Races are Human, Half-Elf, Elf, Halfling, Gnome, Dwarf, Half-Orc, and
Half-Troll. Classes are Warrior, Mage, Priest, Rogue, Ranger, and Paladin.
Not every race can choose every class. Humans and Half-Elves can choose any
class; the stricter race/class limits follow the classic Moria tables.

Experience raises your level, which improves hit points, mana, combat ability,
searching, disarming, saving throws, and spell/prayer access. Level 40 is the
maximum. Different races and classes advance at different rates; powerful
combinations usually require more experience.

Several non-human races have infravision. Infravision can show nearby warm
monsters while you are in darkness across all eight ports. It does not reveal
terrain, items, traps, doors, or cold creatures, and blindness blocks it.
Dwarves have the longest natural infravision; potions and helms of infravision
temporarily or permanently add to the effective range.

## Main Commands

Moria8 uses a unified keymap across all eight platforms. The in-game help screen
is the authoritative quick reference: press `?` (and `L` inside Help to view the
License and Source Offer).

### Movement

| Key | Action |
| --- | ------ |
| `H` / `4` / cursor left | Move west. |
| `L` / `6` / cursor right | Move east. |
| `K` / `8` / cursor up | Move north. |
| `J` / `2` / cursor down | Move south. |
| `Y` / `7` | Move northwest. |
| `U` / `9` | Move northeast. |
| `B` / `1` | Move southwest. |
| `N` / `3` | Move southeast. |
| `5` | Rest or stay for one turn. |
| `CTRL+R` | Rest until HP and mana are recovered (or disturbed). |
| `.` then direction, or `SHIFT` + direction | Run in that direction. |
| `<` | Go up stairs. |
| `>` | Go down stairs. |

Platform movement notes:

- The C128 numeric keypad (`7 8 9 / 4 5 6 / 1 2 3`) also moves and rests (`5`).
- On Atari 8-bit, `Ctrl` + `+` / `*` / `-` / `=` serve as directional arrows.
- On pre-shifted ASCII keyboards (Apple IIe, Atari 8-bit, BBC Master 128, CP/M 2.2
  Z80), uppercase `H J K L Y U B N` act as `SHIFT` + direction to run.
- On CP/M 2.2 (Z80), VT100/ANSI `CSI` (`ESC [ A..D`) and `SS3` (`ESC O A..D`)
  terminal arrow keys also move cardinally.

### Action And Information Keys

| Key | Action |
| --- | ------ |
| `G` or `,` | Get item from the floor. |
| `D` | Drop item. |
| `I` | Inventory (`22` pack slots `a`–`v`). |
| `E` | Equipment (`12` equipped slots). |
| `W` | Wear or wield an item. |
| `T` | Take off equipment. |
| `SHIFT+X` | Exchange primary and secondary weapons. |
| `Q` | Quaff potion. |
| `R` | Read scroll. |
| `A` | Aim wand. |
| `Z` | Use staff. |
| `F` | Study a book to gain a spell/prayer (or browse books when none are pending). |
| `M` | Cast a mage spell. |
| `P` | Pray a priest prayer. |
| `S` | Search adjacent tiles (hidden traps, secret doors, chest traps) for one turn. |
| `#` | Toggle search mode. |
| `O` | Open door or chest (picks locked chests). |
| `C` | Close door. |
| `SHIFT+D` | Disarm a visible adjacent floor trap or revealed chest trap. |
| `CTRL+B` | Bash a door, chest, or monster. |
| `CTRL+D` | Jam a door with an iron spike (`CTRL+D` rather than `CTRL+J` across all ports). |
| `+` | Tunnel through walls, veins, or rubble. |
| `X` | Look in a direction. |
| `/` | Monster recall by monster symbol (`/` + symbol). |
| `SHIFT+C` | Character sheet. |
| `SHIFT+F` | Fire a missile weapon. |
| `SHIFT+T` | Throw an item. |
| `SHIFT+E` | Eat food. |
| `SHIFT+R` | Refuel lantern with oil. |
| `V` or `SHIFT+V` | Version and System Info (build version, Save V2 `$22`, geometry, drives, session info). |
| `=` | *(CP/M 2.2 Z80 only)* Cycle terminal mode (`ADM-3A` / `ANSI Color` / `ANSI Mono`). |
| `CTRL+P` | Message history (last 8 messages). |
| `?` | Help command reference (`L` inside Help opens License / Source Offer). |
| `SHIFT+S` | Save and quit after a successful save. |
| `SHIFT+Q` | Quit without saving (prompts `Y/N`). |
| `CTRL+W` | Wizard/debug mode. Wizard games cannot record high scores. |

At prompts, `ESC`, `RUN/STOP` (`STOP`), or `Q` usually cancels (`Break` maps to
backspace on Atari 8-bit). `SPACE` or `RETURN` continues through messages.
Inventory letters act directly in most item lists.

## The Town

The town is your supply base. It contains the six classic shops plus two
Moria8 extensions:

| Store | Typical Use |
| ----- | ----------- |
| General Store | Food, torches, flasks of oil, cloaks, picks, shovels, spikes. |
| Armory | Body armor, shields, helms, gloves, boots. |
| Weaponsmith | Melee weapons, bows/crossbows/slings, ammunition. |
| Temple | Healing potions, Word of Recall, Remove Curse, prayer books, blunt weapons. |
| Alchemy Shop | Utility scrolls (Word of Recall, Identify, Light, Magic Mapping, enchanting) and Restoration. |
| Magic Shop | Wands, staffs, rings, amulets, mage spellbooks. |
| Black Market | Expensive mixed goods, often outside normal shop limits. |
| Home | Storage (`16` slots, `A`–`P`), not a normal buying/selling shop. |

Charisma affects ordinary store prices. The Black Market uses harsher special
pricing. Stores restock when you return to town.

Buy enough food and light before descending. Running out of either is an early
way to lose a promising character.

## The Dungeon

The dungeon is turn-based. Monsters act after your meaningful actions. Walking
into a monster attacks it. Standing still, searching, resting, eating, reading,
using items, changing equipment, and moving all spend game time.

Important dungeon habits:

- Keep a light source fueled.
- Carry food.
- Search suspicious dead ends, doorways, and chests.
- Retreat before you are nearly dead.
- Do not fight everything at once; corridors are safer than open rooms.
- Use stairs as exits, not just progression.
- Use `X` to look and `/` to check monster recall by symbol.
- Use run carefully; attacks, hazards, and interruptions stop a run.

40-column ports (C64, Plus/4, Atari 8-bit) use `80x48` maps with `38x19`
viewports. 80-column ports (C128, Apple IIe, Commander X16, BBC Master 128,
CP/M 2.2 Z80) use full `198x66` maps (`78x19` viewport on C128; `78x18` on Apple
IIe, Commander X16, BBC Master 128, and CP/M 2.2 Z80), matching classic terminal
Moria geometry while sharing the same core rules.

### Chests

Moria8 implements all six classic chest types (**Small/Large Wooden**,
**Small/Large Iron**, **Small/Large Steel**) plus **Ruined Chests**. Chests can
be locked and armed with hidden traps (poison needles, paralysis gas, explosive
charges, or monster-summoning runes):

- **Search (`S` / `#`):** Search adjacent squares to reveal traps on a chest.
- **Disarm (`SHIFT+D`):** Attempt to disarm revealed chest traps before opening.
- **Open (`O`):** Picks the lock if locked (confusion prevents lock-picking),
  triggers any remaining armed traps, and spills treasure onto nearby floor
  tiles (except explosion traps, which destroy the chest and its contents).
- **Bash (`CTRL+B`):** Breaks open a locked chest by force, turning it into a
  `Ruined Chest` while still triggering any armed traps.

## Items And Equipment

Moria8 ships the full **361-item catalog** (`0`–`360`) and **55 ego item
types** (plus `Gnomish` and `Dwarven` digging tool prefixes). Items may be
unidentified, cursed, magical, or ordinary. Wear/wield decisions matter: cursed
equipment cannot be taken off or replaced until the curse is removed. Heavy
weapons can be poor choices for weak characters even if their damage looks
large.

Inventory uses `22` lettered pack slots (`a`–`v`). Equipment uses `12` fixed
slots:

- Weapon / Digging Tool, Body Armor, Shield, Helm / Crown, Gloves / Gauntlets,
  Boots, Light Source, Ring (right hand), Amulet, Ring (left hand), Cloak, and
  Secondary Weapon (`SHIFT+X` swaps primary and secondary weapons).

Dropping an inventory item compacts the pack, so item letters may change after
removal. Some items are learned by use; potions, scrolls, wands, staffs, rings,
armor, and weapons become safer once identified via `Identify` or trial.

## Combat

Melee is automatic when you move into a monster. Ranged combat uses `SHIFT+F`
to fire a missile weapon (matching bow/crossbow/sling and ammunition) or
`SHIFT+T` to throw an item. `CTRL+B` can bash doors, chests, or monsters; `+`
tunnels through rock and veins.

Armor class reduces your chance of being hit. Weapon bonuses, strength,
dexterity, class, ego slays/brands, and level affect your offense. Monsters
use up to four attacks, 19 attack descriptions, 24 special effects (stat drains,
theft, corrosion, disenchantment, charge/food/light draining, status effects),
and 18 spells/breaths. If a new monster is hurting you faster than you can hurt
it, leave.

Some weapons and stat combinations give more than one melee blow in a single
attack command. When a melee message ends with a count such as `(2/3)`, the
first number is successful hits and the second number is total blows attempted.

Moria8 ships all **279 classic monsters** across all eight platforms with
**persistent Monster Recall** (`/` followed by a monster symbol), saved across
sessions in Save Format V2. See [MONSTERS.md](MONSTERS.md) for the full
279-species roster and threat notes.

## Magic

Mages, Rogues, and Rangers use mage spells. Priests and Paladins use prayers.
Warriors do not cast. Use `F` to study a book when eligible (or browse books),
then `M` to cast or `P` to pray.

Spell and prayer access depends on class, level, book, mana, and the character's
prime stat. Mages care about intelligence; priests and paladins care about
wisdom. Casting beyond your current mana is risky: overcasting raises fail
chance, drains mana to zero, can knock you unconscious, and can damage CON. See
[SPELLS.md](SPELLS.md) for levels, mana costs, fail rates, book placement, and
effect notes.

*(Audio note: six 6502 platforms synthesize all 10 game sound effects; CP/M
2.2 Z80 emits terminal ASCII `BEL` (`0x07`) alerts on key events; Commodore
Plus/4 sound is currently silent.)*

## Winning And Death

The long-term goal is to descend, survive, build enough power, and defeat the
Balrog. You will need strong equipment, reliable escape options, enough hit
points to survive sudden damage, and knowledge of which fights to avoid. After
defeating the Balrog, retiring (`SHIFT+Q`) displays the royal victory crown
screen and awards the winner score bonus.

Unlike the original Moria games, death does not remove your savefile. This
slight deviation allows restoring after death instead of starting over.

For early-game advice, see [PLAYER_GUIDE.md](PLAYER_GUIDE.md). For save, disk,
and emulator troubleshooting, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
