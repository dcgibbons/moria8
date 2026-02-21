# VIC-20 Moria: Feasibility and Architecture Analysis

Based on the C64 implementation of Moria and the constraints of the VIC-20, porting this engine to the VIC-20 is both **highly viable and technically fascinating**, provided we use the constraints you specified.

Here is an analysis of what it would take, what must change, and how it would work:

## 1. Storage & Memory: Disk vs. Cartridge
**Verdict: Cartridge is mandatory; Disk is practically non-viable.**

The C64 implementation uses ~47KB of highly packed monolithic code, plus ~10KB of state (the 3.8KB map, ZP, buffers, screen/color RAM). 
Even with maximum expansion (+35K), the VIC-20 only offers ~40KB of total usable RAM. If loaded from disk, the code simply will not fit in memory alongside the game state. A disk-based approach would require aggressively overlaying 8KB chunks of core engine logic (swapping Combat, Magic, Generation in and out from a 1541 disk drive constantly). The game would be unplayably slow.

**The Cartridge Solution:**
By targeting a modern bank-switched cartridge (such as the Penultimate Cartridge or varying Multi-Carts), the architecture flips to a massive advantage over the C64:
- The 47KB of game code, plus all strings and tables, is burnt to ROM and mapped into the VIC-20's BLK5 cartridge space (`$A000-$BFFF`) in instantly switchable 8KB banks.
- The +35K of RAM becomes **pure state storage**. You have a luxurious amount of RAM for the dungeon map, LRU caches, player state, and zero page, with no risk of running out of memory. 
- You would trade disk I/O loading screens for instantaneous ROM bank jumps via IO register writes.

## 2. Display: 40-Column Mode via Custom Font
The VIC-20 resolution is natively 22 columns by 23 rows. Achieving 40 columns requires "soft-40" rendering (creating a 4x8 pixel custom font and drawing two characters side-by-side into a single 8x8 hardware cell).

**Dynamic Character Allocation:**
The VIC-20 can only address 256 unique custom characters at once. A full screen of text (22x23 = 506 cells) could easily exceed 256 unique *pairs* of characters. How do Tynemouth and others solve this?
- The game engine writes abstract ASCII to a 44x23 logical "virtual buffer" in RAM.
- A custom renderer scans pairs of characters in this buffer. It uses an LRU (Least Recently Used) cache to look up if the pair (e.g., `[` next to `W`) already exists in the 256 custom character slots. 
- If not, it generates the new 8x8 combination graphic on the fly and updates the cache. 
- Because a dungeon viewport is incredibly repetitive (90% of pairs are `wall/wall`, `wall/floor`, or `floor/floor`), the 256 slots are more than sufficient to render the viewport without thrashing the cache.

## 3. What Features Must Be Dropped?

### **A. Multi-Color Tile Displays (The Fatal Compromise)**
In VIC-20 high-res mode, an 8x8 cell can only have **ONE** foreground color from color RAM. Because two 4x8 tiles (e.g., a green Goblin and a yellow Gold Piece) might share the exact same 8x8 hardware cell, they CANNOT have different colors. Whichever color is chosen for the cell applies to both.
* **Dropped:** The C64's per-tile color-coded threat system (red for dangerous, green for easy) and color-coded items.
* **Solution:** The game must run entirely in **Monochrome** (e.g., Amber or Light Green on Black). This fits the retro terminal aesthetic perfectly, entirely side-steps the hardware color clash problem, and drastically speeds up the screen renderer since it no longer has to calculate color RAM offsets.

### **B. Two Rows of Screen Real Estate**
The C64 uses 40x25. The VIC-20 soft-40 uses roughly 44x23. We lose 2 rows. 
* **The Math:** Top messages take 2 rows. Bottom status (HP/SP/Level/Exp) takes 2 rows. This leaves 19 rows for the map.
* **Solution:** Fortunately, the C64 Moria architectural design document (`DESIGN.md`) shows the C64 viewport is *already* exactly 19 rows (38x19). The UI will fit perfectly onto the VIC-20 without modifying the actual map generation bounds!

### **C. SID Sound System**
* **Dropped:** The C64 SID wave/envelope sound effects (`sound.s`).
* **Solution:** Rewritten for the VIC-20's VIA square wave and noise registers. The sound footprint will be simpler but absolutely adequate for bumps, hits, misses, and leveling up.

## 4. Could It Work At All?
**Yes, absolutely.** 

In fact, if built as a 512KB banked cartridge utilizing +35K of expansion RAM, the VIC-20 version of Moria would arguably run **faster** and have fewer loading transitions than the disk-based C64 version. 

**What needs to be done:**
1. **Refactor Architecture for Banks**: Extract `main.s` into an 8KB core kernel that executes cross-bank jumps to disparate modules (Combat bank, Generation bank, GUI bank) located in ROM.
2. **Virtual Renderer Swap**: Strip out the `$0400` direct screen writes and `$D800` color writes, replacing them with a virtual buffer and a monochrome soft-40 LRU character stitcher.
3. **Migrate State**: Shift the map and BSS to the immense +35K expansion RAM block (`$2000-$5FFF`).

It is a completely practical project that perfectly fits the capabilities of a fully expanded, cartridge-equipped VIC-20.

## 5. Alternative: Natural 22-Column Screen Viability
If we abandon the soft-40 custom font and target the VIC-20's natural 22x23 hardware resolution, the project is still viable, but the trade-offs invert entirely:

**Advantages (What we gain):**
1. **Full Color Returns:** Because we are using 1:1 hardware character cells, we no longer suffer the color clash of drawing two 4x8 characters into one 8x8 cell. The game can have multi-color tiles just like the C64 version!
2. **Faster Performance:** Direct hardware screen RAM and color RAM writes are lightning fast. The CPU overhead of the soft-40 virtual buffer, LRU cache searching, and bit-shifting are completely eliminated.
3. **Simplicity:** The display architecture remains a near 1:1 port of the C64's `screen.s`, simply adapted for different memory addresses.

**Disadvantages (What must change):**
1. **Claustrophobic Viewport:** The C64 dungeon viewport is 38x19 tiles. On the VIC-20, after reserving ~5 rows for UI messages and status, the viewport would shrink to roughly **22x18**. You will see far less of the dungeon horizontally, which changes gameplay balance (ranged combat and escaping become harder on the X-axis).
2. **Total UI Redesign:** Every screen in the game assumes 40 columns.
   * **Status Bar:** The C64 status strings are ~34 characters wide (e.g., `Moria  Dlvl:3  HP:45/45  MP:12/15`). This would need to be split into a 3 or 4-row block.
   * **Message Line:** Game messages usually exceed 22 characters. A robust word-wrap and paging system is mandatory.
   * **Inventory/Stores:** Item lines (e.g., `a) 3 Rations of Food [2]`) take 24+ characters. Lists would require aggressive abbreviation or multi-line entries, making them much harder to read.

**Verdict:** It is completely viable and would make the *rendering backend* far simpler and faster, but it would require a massive front-end overhaul of almost every single text string and UI framing routine in the entire codebase.
