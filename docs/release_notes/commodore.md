# Moria8 Commodore Release Notes

Moria8 brings the Moria and Umoria dungeon-crawling model to the Commodore 64
and Commodore 128 through platform-specific memory, display, storage, and
runtime adaptations. These ports are lineage-faithful and hardware-adapted, not
byte-identical reproductions of VMS Moria or Umoria.

These ports support both the classic C64 and C128 hardware, VICE emulators,
and the FPGA based C64 Ultimate from [Commodore](https://commodore.net/computer/).

## Version History

### v1.0.0 - Initial Commodore Release

Initial release of the Commodore ports:

- Commodore 64 disk image: `moria8-c64.d64`
- Commodore 128 disk image: `moria8-c128.d71`
- Shared gameplay foundation across both Commodore targets.
- Platform-specific display, loader, memory, and disk-image implementations.
- Validation through VICE and real Commodore 64 and Commodore 128 hardware.

## Platform Notes

### Commodore 64

The C64 port is the most aggressively constrained Moria8 target. It uses a
40-column PETSCII display, a compact `80x48` dungeon map, runtime overlays, and
disk or REU-backed creature tier loading to fit the game into the C64 memory
model.

Compared with terminal Moria and Umoria, the C64 version necessarily compresses
the interface and presentation. It keeps the recognizable gameplay shape while
adapting map storage, visible layout, resident data, and loading behavior to a
machine where RAM and display width are central design constraints.

### Commodore 64 Ultimate

The best results for the C64 Ultimate is to enable the REU feature to allow
for less disk swapping while playing.

### Commodore 128

The C128 port uses the 80-column VDC display, making its presentation closer to
classic terminal Moria than the C64 version. It also uses the C128 MMU, Bank 1
map/data/cache ownership, and runtime-loaded payloads to support a broader
active feature surface than would fit in one flat 6502 address space.

The C128 version shares gameplay logic with the C64 port, but it is not just a
wider-screen build. Its memory layout, display backend, loader behavior, and
runtime ownership model are C128-specific.

## Compared With VMS Moria And Umoria

Moria8 uses VMS Moria and Umoria as lineage and behavior references, not as
literal compatibility targets. Save files, memory layout, source layout,
terminal behavior, exact message timing, and exact data shape are not expected
to match either upstream.

Where VMS Moria and Umoria diverge materially, Moria8 may prefer VMS-informed
gameplay behavior. Umoria remains the major reference for the C-language lineage
and for class, book, and spell catalog structure.

The Commodore builds include the full `31` mage spell and `31` priest prayer
catalogs. Class and book access follow Umoria, while spell behavior follows the
port's Moria/VMS/Umoria reconciliation policy. Some textual feedback and timed
expiry messages are intentionally reduced or omitted where the Commodore ports
need tighter display or memory behavior.

## Known Scope And Limits

Moria8 is not a byte-for-byte Umoria reproduction. Some full-content breadth is
staged or reduced for the Commodore memory, display, and storage model.

Known port-scope limits include:

- Monster recall persistence is not complete.
- The ports do not guarantee terminal-perfect UI, message text, or timing.
- Disk loading, load timing, and memory-expansion behavior can differ between
  C64, C64 with REU, and C128.
- Custom fastloader work and long-term platform polish remain future work.

## Capability Matrix

This matrix summarizes broad player-visible capability areas for the initial
Commodore release. It is not a command-by-command or data-by-data parity claim
against VMS Moria or Umoria.

| Feature Area | C64 | C128 | Notes |
| ------------ | --- | ---- | ----- |
| Bootable disk image | Yes | Yes | C64 ships as `.d64`; C128 ships as `.d71`. |
| Character creation | Yes | Yes | Shared race, class, stat, history, and starting-equipment flow. |
| Town and ordinary stores | Yes | Yes | Includes the six classic Moria/Umoria stores: General Store, Armory, Weaponsmith, Temple, Alchemy Shop, and Magic Shop. |
| Black Market and Home | Yes | Yes | Included as Moria-family/Angband-style extensions, not standard six-store Umoria town features. |
| Dungeon generation | Yes | Yes | C64 uses a compact map; C128 uses a larger banked map/data model. |
| Dungeon exploration | Yes | Yes | Movement, light, doors, traps, stairs, searching, tunneling, and related core dungeon interactions are present. |
| Combat | Yes | Yes | Shared melee, ranged, thrown, damage, experience, and level-up systems. |
| Monsters | Partial | Partial | 120 selected creatures from Umoria's 279-creature catalog, arranged into overlapping town/shallow/early/mid/deep tiers; includes deep threats, Evil Iggy, and Balrog, but not the full upstream roster. |
| Items and inventory | Partial | Partial | Core inventory, equipment, floor items, stores, identification, and item use are present with reduced full-content breadth. |
| Mage spells | Yes | Yes | Full `31` spell catalog; class/book access follows Umoria. |
| Priest prayers | Yes | Yes | Full `31` prayer catalog; class/book access follows Umoria. |
| Save/load | Yes | Yes | Platform-specific disk/runtime implementation. |
| High scores | Yes | Yes | Saved through the Commodore disk I/O path. |
| Monster recall display | Partial | Partial | Recall display exists; recall persistence is not complete. |
| 40-column display | Yes | No | C64 PETSCII display path. |
| 80-column display | No | Yes | C128 VDC display path. |
| REU-assisted loading | Yes | Not applicable | C64 can use REU-backed creature tier loading; C128 uses its own banked memory model. |
