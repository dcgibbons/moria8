# Moria C64/C128 Project Audit

## 1. Feature Comparison

### a) Features in `vms-moria` not present in `moria8`
- **Map Size**: Original is 66 rows x 198 columns. `moria8` is 48 rows x 80 columns (split into 4 screens).
- **Monster Count**: Original has ~351 monsters. `moria8` has 160 monsters (Tier 0: 8, Tier 1: 24, Tier 2: 32, Tier 3: 39, Tier 4: 57).
- **Item Count**: Original has ~400+ item templates. `moria8` has only 55 base item types.
- **Active Monsters**: Original allows ~100+ active monsters. `moria8` caps at 32 active monsters per level due to RAM constraints.
- **Haggling**: `vms-moria` has a complex haggling system where charisma impacts price negotiation. `moria8` uses a simplified "Simplified Haggling" model (accept/decline at calculated price).
- **Party Mode**: Some variations of `vms-moria` had experimental party support. `moria8` is strictly single-player.
- **Save Scumming Prevention**: `moria8` deletes the save file upon loading, enforcing permadeath. This matches the spirit but is technically a "feature" present in the port that enforces the rule strictly.
- **Stores**: Original has 8 stores (including Black Market and Home). `moria8` has 6 stores (General, Armory, Weapon, Temple, Alchemy, Magic). Missing: Black Market and Player Home (Storage).

### b) Features in `umoria` not present in `moria8`
- **Character History**: `umoria` generates a detailed text history for the character background. `moria8` has a streamlined creation process.
- **Artifacts**: Original has fixed artifacts (e.g. Phial of Galadriel). `moria8` **does not implement fixed artifacts**.
- **Ego Items**: Original has ego items (e.g. "Long Sword of Slay Orc"). `moria8` implements basic enchantment (+x to hit/dmg) but **no complex ego powers** or slay flags are visible in the item structure.
- **Detailed Inscriptions**: `umoria` allows inscribing items with custom text (e.g. "{empty}"). `moria8` does not support custom string inscriptions.
- **Grouping**: `moria8` implements basic stacking, but advanced grouping options (like in modern Angband variants) are not present.

## 2. Bugs in Implemented Features

### Known Bugs (from BUILDPLAN & Analysis)
- **Input Lag**: `BUILDPLAN.md` notes "Full viewport redraw on every move causes visible input lag". This was marked as fixed, but should be verified in playtesting.
- **Key Stacking**: "Keyboard buffer not flushed before input poll" was identified and fixed.

### Potential Issues
- **Monster AI Stack Depth**: The recursive or deep call chains (main -> move -> combat -> effects) can risk stack overflow on 6502 (only 256 bytes stack). `BUILDPLAN.md` identifies this as a risk.
- **Memory Safety**: `screen_clear` had a bug writing past screen RAM, marked as fixed.
- **Item Generation**: Random generation logic in `item.s` is simplified (Phase 1 gold, Phase 2 items). It might not match the distribution curves of the original.

## 3. Code Quality Issues

### TODOs (from Source Scan)
- `input.s`: Numeric prefix parsing is marked as deferred/broken in `BUILDPLAN`.
- `BUILDPLAN.md` lists many TODOs for Phase 10 (C128 features), such as 80-column mode, extended memory usage, and larger dungeon.
- `store.s`: `Black Market` and `Player Home` are listed as TODO in `BUILDPLAN`. `store.s` code confirms they are missing.
- `player_magic.s`: Full spellbook set is incomplete (only 2 books implemented, 8 total in original).
- `dungeon_gen.s`: Room placement is random; originally it used a specific grid logic.

### Refactoring Needs
- **Large Files**: `dungeon_gen.s` (60KB) and `item.s` (52KB) are very large single files. They should be split into sub-modules (e.g., `dungeon_gen_rooms.s`, `dungeon_gen_corridors.s`).
- **Hardcoded Values**: Tier data generation scripts (`parse_creatures.py`, mentioned in headers) suggest a good pipeline, but the assembly files themselves contain many magic numbers for colors and attributes that could be symbolic.
- **Magic Numbers**: `item.s` uses raw indices (0-54) for item types in many places effectively hardcoding the table order.

## 4. Product Quality / Playability Issues

### Screen Constraints
- **40 Column Display**: The original game assumes 80 columns. The 40-column viewport requires scrolling or panel switching, which significantly changes the tactical awareness.
- **Message Truncation**: Messages often exceed 40 characters. The "—more—" prompt usage is critical and might be intrusive if too frequent.

### Performance
- **Disk I/O**: Tier transitions require loading data from disk. On a stock 1541, this is slow (~30s). A fastloader is required and implemented, but real hardware performance is a key playability factor.
- **Turn Speed**: Generating a level or processing 32 monsters might be slow on a 1MHz 6502 compared to a VAX. `BUILDPLAN.md` notes this risk.

### Balance
- **Reduced Content**: With fewer monsters (160 vs 351) and items (55 vs 400+), the game balance (XP gain, drop rates) needs careful tuning to match the original's progression curve.
- **Spell Variety**: Reduced spell list (32 vs 62+) changes the utility of caster classes.
- **Lack of Artifacts**: The endgame might feel less rewarding without the chase for specific named artifacts.

## 5. Architecture & Physical Build

### Single Binary Tax
The current "Single Binary" plan (detect C128 at runtime, adapt behavior) imposes a significant penalty on the C64 version.
- **Dead Code**: C64 users must load VDC drivers and MMU logic they cannot use.
- **Memory Pressure**: The ~2-4KB wasted on C128 support code could otherwise store ~20 more active monsters or reduce disk thrashing.
- **Complexity**: Runtime checks for `MACHINE_C128` add overhead to tight loops (screen rendering).

### Recommendation: Separate Binaries
The project should pivot to a "Universal Loader" model:
1.  **BOOT.PRG**: Tiny launcher that detects the machine.
2.  **MORIA64.PRG**: Optimized strictly for 64KB. No VDC code. Maximize RAM for gameplay.
3.  **MORIA128.PRG**: Optimized for 128KB + 80 columns. Keep entire database in RAM (no disk loading pauses).

This solves the memory constraint on 100% of C64s while allowing the C128 version to realize its "Full Experience" potential without being held back.

### Hardware Utilization (REU)
The current codebase includes **REU (Ram Expansion Unit)** support (`reu.s`).
- **Cost**: ~400 bytes of code.
- **Benefit**: If detected, all 4 monster tiers are loaded to the REU at startup. Tier transitions become instant (DMA) instead of slow disk loads.
- **Verdict**: **Keep it.** The code cost is negligible (<1%) for a massive playability gain. It aligns perfectly with the "Separate Binaries" strategy (as `MORIA64.PRG` can simply include the module).

## 6. UX & Polish

### Directory Art
- **Requirement**: The disk directory listing should look professional and thematic.
- **Implementation**: Use PETSCII art characters in filenames (0-length files or dummy files) to create a logo or title ("DUNGEONS OF MORIA") that appears when the user types `LOAD "$",8` and `LIST`.

## 7. File Naming Review

### Current State
| Usage | Filename | Source File | Notes |
| :--- | :--- | :--- | :--- |
| **Save Game** | `MORIA.SAV` | `save.s` | Functional but generic. |
| **High Scores** | `MORIA.HI` | `score.s` | Standard generic extension. |
| **Tier Data** | `CR T1` - `CR T4` | `tier_manager.s` | Very cryptic. Looks like debug names. |

### Recommendations
1.  **Save Game**: Rename to **`THE.GAME`**.
    *   *Why*: It adds a classic flair (referencing old Infocom or RPG styles) and looks cleaner in the directory.
2.  **High Scores**: Rename to **`HALL.OF.FAME`**.
    *   *Why*: Much more thematic than `MORIA.HI`.
3.  **Tier Data**: Rename to **`MONSTER.DB.1`**, **`MONSTER.DB.2`**, etc.
    *   *Why*: "CR T1" is obscure. Users browsing the disk should know what these files are (and that they shouldn't delete them).

## 8. Release Strategy & Data Persistence

### The Update Problem
If the game and save data reside on the same disk image, releasing a new version (`moria8_v1.1.d64`) forces the user to lose their save file (`THE.GAME`) and high scores (`HALL.OF.FAME`) unless they manually copy files. This is a poor user experience.

### Recommendation: The "Character Disk"
The standard RPG solution on C64 is to separate the **Game Disk** (read-only code & static data) from the **Character Disk** (read/write save & high score data).

1.  **Boot & Play**: User boots the Game Disk.
2.  **Save/Load**: when the user attempts to Save, Load, or view High Scores, the game prompts:
    > `PLEASE INSERT SAVE DISK AND PRESS RETURN`
3.  **Update Safety**: A new game version is just a new Game Disk. The user keeps their existing Character Disk, preserving all progress and high scores across engine updates.

### Implementation Requirements
- Code needs to handle disk swapping (wait for keypress, re-initialize drive if needed).
- Code needs to handle "Wrong Disk" errors gracefully (check for a specific ID file on the Save Disk).
