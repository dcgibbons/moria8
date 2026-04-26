# Wizard Mode

This file documents the current Wizard Mode controls in this tree.

## Entering Wizard Mode

- Press `Ctrl+W`
- First activation asks `WIZARD? (Y/N)`
- Press `Y` to enable it

Notes:
- Wizard state is tracked with `GAME_FLAG_WIZARD`
- Wizard runs are marked as non-ranked in score displays

## Wizard Menu

After Wizard Mode is enabled, press `Ctrl+W` again to open the wizard menu.

Commands:
- `L` — jump to dungeon level
- `A` — reveal the current level
- `H` — full heal / cure statuses / restore mana
- `I` — identify all carried items
- `X` — gain one level
- `G` — generate an item by item ID
- `S` — summon a monster adjacent to the player
- `T` — teleport the player
- `W` — toggle wall-walk
- `Q` — cancel / exit menu

Prompts:
- Item generation: `ITEM 0-63: `
- Level jump: `DLVL 0-99: `

Feedback:
- Success: `OK`
- Failure: `FAIL`
- Bad numeric input: `BAD`
- Wall walk toggle: `WALL ON` / `WALL OFF`

## Generate Item

Wizard item generation uses item IDs `0-63`.

Behavior:
- Non-gold items try to go into inventory first
- If inventory is full, they fall back to the floor at the player tile
- Gold always becomes floor gold
- Missiles may generate in small stacks

## Common Workflows

### Spawn specific books

- Mage book 1: `Ctrl+W`, `G`, `47`
- Priest book 1: `Ctrl+W`, `G`, `48`
- Mage book 2: `Ctrl+W`, `G`, `55`
- Mage book 3: `Ctrl+W`, `G`, `56`
- Mage book 4: `Ctrl+W`, `G`, `57`
- Priest book 2: `Ctrl+W`, `G`, `58`
- Priest book 3: `Ctrl+W`, `G`, `59`
- Priest book 4: `Ctrl+W`, `G`, `60`

### Jump to a dungeon level

- `Ctrl+W`, `L`, then enter a level `0-99`
- `0` returns to town

### Reveal the current floor

- `Ctrl+W`, `A`

This reveals the current level layout without requiring detection spells.

### Full recovery

- `Ctrl+W`, `H`

This:
- heals HP to full
- restores mana
- clears poison, blindness, confusion, paralysis, fear, recall timer, and speed timer

### Test poison cures

Wizard Mode does not have a direct command to set poison. To test `Cure Poison`
or `Neutralize Poison` feedback:

1. Generate a poison potion: `Ctrl+W`, `G`, `19`
2. Quaff the generated potion with `q`
3. Cast `Cure Poison` or pray `Neutralize Poison`
4. Expected result: poison clears and `You feel better.` is printed
5. Cast/pray the same row again while already clear; it should remain silent

### Generate common test items

- Cure Light Wounds potion: `17`
- Cure Serious Wounds potion: `25`
- Restore Mana potion: `26`
- Wand of Lightning: `40`
- Wand of Frost: `41`
- Staff of Detect Monsters: `44`
- Staff of Cure Light Wounds: `46`
- Flask of Oil: `61`

### Movement / traversal helpers

- Toggle wall walk: `Ctrl+W`, `W`
- Teleport: `Ctrl+W`, `T`
- Summon adjacent monster: `Ctrl+W`, `S`

## Item IDs

| ID | Item |
|---:|---|
| 0 | Gold (small) |
| 1 | Gold (large) |
| 2 | Dagger |
| 3 | Short sword |
| 4 | Long sword |
| 5 | Mace |
| 6 | Robe |
| 7 | Leather armor |
| 8 | Chain mail |
| 9 | Small shield |
| 10 | Iron helm |
| 11 | Leather gloves |
| 12 | Leather boots |
| 13 | Wooden torch |
| 14 | Brass lantern |
| 15 | Ration of food |
| 16 | Slime mold |
| 17 | Cure light wounds |
| 18 | Speed |
| 19 | Poison |
| 20 | Light |
| 21 | Identify |
| 22 | Teleportation |
| 23 | Protection |
| 24 | Strength |
| 25 | Cure Serious Wounds |
| 26 | Restore Mana |
| 27 | Heroism |
| 28 | Blindness |
| 29 | Confusion |
| 30 | Detect Monsters |
| 31 | Infravision |
| 32 | Word of Recall |
| 33 | Remove Curse |
| 34 | Enchant Weapon |
| 35 | Enchant Armor |
| 36 | Monster Confusion |
| 37 | Aggravate |
| 38 | Protect from Evil |
| 39 | Wand of Light |
| 40 | Wand of Lightning |
| 41 | Wand of Frost |
| 42 | Wand of Stinking Cloud |
| 43 | Staff of Light |
| 44 | Staff of Detect Monsters |
| 45 | Staff of Teleportation |
| 46 | Staff of Cure Light Wounds |
| 47 | Beginner's Spellbook (Mage Book 1) |
| 48 | Holy Prayer Book (Priest Book 1) |
| 49 | Short Bow |
| 50 | Light Crossbow |
| 51 | Sling |
| 52 | Arrow |
| 53 | Bolt |
| 54 | Rock |
| 55 | Magick I (Mage Book 2) |
| 56 | Magick II (Mage Book 3) |
| 57 | The Mages Guide to Power (Mage Book 4) |
| 58 | Words of Wisdom (Priest Book 2) |
| 59 | Chants and Blessings (Priest Book 3) |
| 60 | Exorcism and Dispelling (Priest Book 4) |
| 61 | Flask of Oil |
| 62 | Shovel |
| 63 | Pick |

## Source References

- Wizard command dispatch: [commodore/common/wizard.s](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-spells/commodore/common/wizard.s)
- C128 wizard UI menu: [commodore/common/ui_wizard.s](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-spells/commodore/common/ui_wizard.s)
- Item IDs: [commodore/common/item_tables.s](/Users/chadwick/Library/Mobile%20Documents/com~apple~CloudDocs/Projects/6502/moria8-spells/commodore/common/item_tables.s)
