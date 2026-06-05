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
- `L` - jump to dungeon level
- `A` - reveal the current level
- `H` - full heal / cure statuses / restore mana
- `I` - identify all carried items
- `X` - gain one level
- `G` - generate an item by item ID
- `S` - summon a monster adjacent to the player
- `T` - teleport the player
- `W` - toggle wall-walk
- `Q` - cancel / exit menu

Prompts:
- Item generation: `ITEM 0-69: `
- Level jump: `DLVL 0-99: `

Feedback:
- Success: `OK`
- Failure: `FAIL`
- Bad numeric input: `BAD`
- Wall walk toggle: `WALL ON` / `WALL OFF`

## Generate Item

Wizard item generation uses item IDs `0-69`.

Behavior:
- Non-gold items try to go into inventory first
- If inventory is full, they fall back to the floor at the player tile
- Gold always becomes floor gold
- Missiles may generate in small stacks

## Common Workflows

### Spawn specific books

- Spellbook Beginners-Magick: `Ctrl+W`, `G`, `47`
- Holy Book of Prayers Beginners Handbook: `Ctrl+W`, `G`, `48`
- Spellbook Magick I: `Ctrl+W`, `G`, `55`
- Spellbook Magick II: `Ctrl+W`, `G`, `56`
- Spellbook The Mages Guide to Power: `Ctrl+W`, `G`, `57`
- Holy Book of Prayers Words of Wisdom: `Ctrl+W`, `G`, `58`
- Holy Book of Prayers Chants and Blessings: `Ctrl+W`, `G`, `59`
- Holy Book of Prayers Exorcism: `Ctrl+W`, `G`, `60`

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

- Potion of Cure Light Wounds: `17`
- Potion of Cure Serious Wounds: `25`
- Potion of Restore Mana: `26`
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
| 17 | Potion of Cure Light Wounds |
| 18 | Potion of Speed |
| 19 | Potion of Poison |
| 20 | Scroll of Light |
| 21 | Scroll of Identify |
| 22 | Scroll of Teleportation |
| 23 | Ring of Protection |
| 24 | Ring of Strength |
| 25 | Potion of Cure Serious Wounds |
| 26 | Potion of Restore Mana |
| 27 | Potion of Heroism |
| 28 | Potion of Blindness |
| 29 | Potion of Confusion |
| 30 | Potion of Detect Monsters |
| 31 | Potion of Infravision |
| 32 | Scroll of Word of Recall |
| 33 | Scroll of Remove Curse |
| 34 | Scroll of Enchant Weapon |
| 35 | Scroll of Enchant Armor |
| 36 | Scroll of Monster Confusion |
| 37 | Scroll of Aggravate |
| 38 | Scroll of Protect from Evil |
| 39 | Wand of Light |
| 40 | Wand of Lightning |
| 41 | Wand of Frost |
| 42 | Wand of Stinking Cloud |
| 43 | Staff of Light |
| 44 | Staff of Detect Monsters |
| 45 | Staff of Teleportation |
| 46 | Staff of Cure Light Wounds |
| 47 | Spellbook Beginners-Magick |
| 48 | Holy Book of Prayers Beginners Handbook |
| 49 | Short Bow |
| 50 | Light Crossbow |
| 51 | Sling |
| 52 | Arrow |
| 53 | Bolt |
| 54 | Rock |
| 55 | Spellbook Magick I |
| 56 | Spellbook Magick II |
| 57 | Spellbook The Mages Guide to Power |
| 58 | Holy Book of Prayers Words of Wisdom |
| 59 | Holy Book of Prayers Chants and Blessings |
| 60 | Holy Book of Prayers Exorcism |
| 61 | Flask of Oil |
| 62 | Shovel |
| 63 | Pick |
| 64 | Main Gauche |
| 65 | Studded Leather Armor |
| 66 | Rapier |
| 67 | Broad Sword |
| 68 | Bastard Sword |
| 69 | Two-Handed Sword |

## Source References

- Wizard command dispatch: `commodore/common/wizard.s`
- Wizard UI menu: `commodore/common/ui_wizard.s`
- Item IDs: `commodore/common/item_tables.s`
