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
- Item generation: `ITEM 0-360: ` (up to 3 digits)
- Level jump: `DLVL 0-99: `

Feedback:
- Success: `OK`
- Failure: `FAIL`
- Bad numeric input: `BAD`
- Wall walk toggle: `WALL ON` / `WALL OFF`

## Generate Item

Wizard item generation uses item IDs `0-360` (defined in
`platforms/shared/item_catalog/item_catalog_spec.json` and generated into
`item_ids.s`, `item_hot_tables.s`, and `ITEM.CAT`) organized in contiguous VMS
Moria 4.8 category and `object_list` order under Base-255 Paged 9-bit IDs:
- **Page 0 (`0-254`, `item_cur_page = $00`):** Gold (`0-19`), Food (`20-49`),
  Potions (`50-94`), Scrolls (`95-136`), Wands (`137-160`), Staves (`161-185`),
  Books (`186-193`: Mage `186-189`, Priest `190-193`), Light & Oil (`194-196`),
  Iron Spike (`197`), Digging Tools (`198-203`), Chests (`204-210`), Cloak (`211`),
  Body Armor (`212-233`), Ranged Launchers & Ammo (`234-243`), Helms & Crowns
  (`244-251`), and Boots (`252-254`).
- **Page 1 (`255-360`, `item_cur_page = $40`, `slot_lo = id - 255`):** Gloves
  (`255-256`), Shields (`257-262`), Melee Weapons (`263-308`), Rings (`309-339`),
  Amulets (`340-349`), and Junk (`350-360`). `$FF` is empty on both pages.

Behavior:
- Non-gold items try to go into inventory first
- If inventory is full, they fall back to the floor at the player tile
- Gold always becomes floor gold
- Ammunition (Arrow, Bolt, Rock, Iron Shot) comes in a stack of 5-10 (`core/wizard.s`;
  dungeon stacks are 7d6 and store stacks 24)
- Enchantment and ego are rolled as for a floor item at the current dungeon
  level (`roll_enchantment`, `roll_ego_type`): a weapon ego, a resistance
  armour or a crown of the Magi comes only by chance, likelier deeper (a
  crown of the Magi is about 1 in 60 of the enchanted crowns made on DL50)

## Common Workflows

### Spawn specific books

- Spellbook Beginners-Magick: `Ctrl+W`, `G`, `186`
- Spellbook Magick I: `Ctrl+W`, `G`, `187`
- Spellbook Magick II: `Ctrl+W`, `G`, `188`
- Spellbook The Mages Guide to Power: `Ctrl+W`, `G`, `189`
- Holy Book of Prayers Beginners Handbook: `Ctrl+W`, `G`, `190`
- Holy Book of Prayers Words of Wisdom: `Ctrl+W`, `G`, `191`
- Holy Book of Prayers Chants and Blessings: `Ctrl+W`, `G`, `192`
- Holy Book of Prayers Exorcism: `Ctrl+W`, `G`, `193`

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

1. Generate a poison potion: `Ctrl+W`, `G`, `71`
2. Quaff the generated potion with `q`
3. Cast `Cure Poison` or pray `Neutralize Poison`
4. Expected result: poison clears and `You feel better.` is printed
5. Cast/pray the same row again while already clear; it should remain silent

### Generate common test items

- Potion of Cure Light Wounds: `62`
- Potion of Cure Serious Wounds: `63`
- Potion of Restore Mana: `93`
- Wand of Lightning: `138`
- Wand of Frost: `139`
- Staff of Detect Invisible: `176`
- Staff of Cure Light Wounds: `175`
- Flask of Oil: `196`
- Launchers: Short Bow `234`, Long Bow `235`, Composite Bow `236`, Light Crossbow `237`, Heavy Crossbow `238`, Sling `239`; ammunition: Arrow `240`, Bolt `241`, Rock `242`, Iron Shot `243`. Wield the launcher, then `SHIFT+F` fires the first
  matching ammunition in the pack.
- Resistance jewellery: Ring of Lordly Protection (Fire) `323`, (Acid) `324`, (Cold) `325`; Amulet of Resist Acid `347`. Wear one and check the breath or
  touch damage of its element.
- Crowns: Silver `249`, Golden `250`, Jewel Encrusted `251`.
- Attack wands (VMS): Fire Bolts `140` (6d8), Drain Life `148` (50, not the
  undead), Lightning Balls `155` (24), Acid Balls `159` (40). Aim one at a
  creature, and at an undead one for Drain Life (no effect).

### Movement / traversal helpers

- Toggle wall walk: `Ctrl+W`, `W`
- Teleport: `Ctrl+W`, `T`
- Summon adjacent monster: `Ctrl+W`, `S`

## Item IDs

| ID | Item |
|---:|---|
| 0 | Gold (small) |
| 1 | Gold (large) |
| 2 | Copper |
| 3 | Copper |
| 4 | Copper |
| 5 | Silver |
| 6 | Silver |
| 7 | Silver |
| 8 | Garnets |
| 9 | Garnets |
| 10 | Gold |
| 11 | Gold |
| 12 | Gold |
| 13 | Opals |
| 14 | Sapphires |
| 15 | Gold |
| 16 | Rubies |
| 17 | Diamonds |
| 18 | Emeralds |
| 19 | Mithril |
| 20 | Mushroom of Poison |
| 21 | Mushroom of Blindness |
| 22 | Mushroom of Paranoia |
| 23 | Mushroom of Confusion |
| 24 | Mushroom of Hallucination |
| 25 | Mushroom of Cure Poison |
| 26 | Mushroom of Cure Blindness |
| 27 | Mushroom of Cure Paranoia |
| 28 | Mushroom of Cure Confusion |
| 29 | Mushroom of Weakness |
| 30 | Mushroom of Unhealth |
| 31 | Mushroom of Restore Constitution |
| 32 | Mushroom of First-Aid |
| 33 | Mushroom of Minor Cures |
| 34 | Mushroom of Light Cures |
| 35 | Mushroom of Restoring |
| 36 | Hairy Mold of Poison |
| 37 | Hairy Mold of Hallucinations |
| 38 | Hairy Mold of Cure Poison |
| 39 | Hairy Mold of Unhealth |
| 40 | Hairy Mold of Cure Serious Wounds |
| 41 | Ration of Food |
| 42 | Slime Mold |
| 43 | Piece of Elvish Waybread |
| 44 | Piece of Elvish Waybread |
| 45 | Pint of Fine Grade Mush |
| 46 | Hard Biscuit |
| 47 | Strip of Beef Jerky |
| 48 | Pint of Fine Ale |
| 49 | Pint of Fine Wine |
| 50 | Potion of Gain Strength |
| 51 | Potion of Weakness |
| 52 | Potion of Restore Strength |
| 53 | Potion of Gain Intelligence |
| 54 | Potion of Lose Intelligence |
| 55 | Potion of Restore Intelligence |
| 56 | Potion of Gain Wisdom |
| 57 | Potion of Lose Wisdom |
| 58 | Potion of Restore Wisdom |
| 59 | Potion of Charisma |
| 60 | Potion of Ugliness |
| 61 | Potion of Restore Charisma |
| 62 | Potion of Cure Light Wounds |
| 63 | Potion of Cure Serious Wounds |
| 64 | Potion of Cure Critical Wounds |
| 65 | Potion of Healing |
| 66 | Potion of Gain Constitution |
| 67 | Potion of Gain Experience |
| 68 | Potion of Sleep |
| 69 | Potion of Blindness |
| 70 | Potion of Confusion |
| 71 | Potion of Poison |
| 72 | Potion of Speed |
| 73 | Potion of Slowness |
| 74 | Icky Green Potion of Slime Mold Juice |
| 75 | Light Brown Potion of Apple Juice |
| 76 | Clear Potion of Water |
| 77 | Potion of Gain Dexterity |
| 78 | Potion of Restore Dexterity |
| 79 | Potion of Restore Constitution |
| 80 | Potion of Learning |
| 81 | Potion of Lose Memories |
| 82 | Potion of Salt Water |
| 83 | Potion of Invulnerability |
| 84 | Potion of Heroism |
| 85 | Potion of Super Heroism |
| 86 | Potion of Boldness |
| 87 | Potion of Restore Life Levels |
| 88 | Potion of Resist Heat |
| 89 | Potion of Resist Cold |
| 90 | Potion of Detect Invisible |
| 91 | Potion of Slow Poison |
| 92 | Potion of Neutralize Poison |
| 93 | Potion of Restore Mana |
| 94 | Potion of Infravision |
| 95 | Scroll of Enchant Weapon To-Hit |
| 96 | Scroll of Enchant Weapon To-Dam |
| 97 | Scroll of Enchant Armor |
| 98 | Scroll of Identify |
| 99 | Scroll of Remove Curse |
| 100 | Scroll of Light |
| 101 | Scroll of Summon Monster |
| 102 | Scroll of Phase Door |
| 103 | Scroll of Teleportation |
| 104 | Scroll of Teleport Level |
| 105 | Scroll of Monster Confusion |
| 106 | Scroll of Magic Mapping |
| 107 | Scroll of Sleep Monster |
| 108 | Scroll of Rune of Protection |
| 109 | Scroll of Treasure Detection |
| 110 | Scroll of Object Detection |
| 111 | Scroll of Trap Detection |
| 112 | Scroll of Trap Detection |
| 113 | Scroll of Door/Stair Location |
| 114 | Scroll of Door/Stair Location |
| 115 | Scroll of Mass Genocide |
| 116 | Scroll of Detect Invisible |
| 117 | Scroll of Aggravate |
| 118 | Scroll of Trap Creation |
| 119 | Scroll of Trap/Door Destruction |
| 120 | Scroll of Door Creation |
| 121 | Scroll of Recharging |
| 122 | Scroll of Genocide |
| 123 | Scroll of Darkness |
| 124 | Scroll of Protect from Evil |
| 125 | Scroll of Create Food |
| 126 | Scroll of Dispel Undead |
| 127 | Scroll of *Enchant Weapon* |
| 128 | Scroll of Curse Weapon |
| 129 | Scroll of *Enchant Armor* |
| 130 | Scroll of Curse Armor |
| 131 | Scroll of Summon Undead |
| 132 | Scroll of Blessing |
| 133 | Scroll of Holy Chant |
| 134 | Scroll of Holy Prayer |
| 135 | Scroll of Word of Recall |
| 136 | Scroll of *Destruction* |
| 137 | Wand of Light |
| 138 | Wand of Lightning |
| 139 | Wand of Frost |
| 140 | Wand of Fire Bolts |
| 141 | Wand of Stone-to-Mud |
| 142 | Wand of Polymorph |
| 143 | Wand of Heal Monster |
| 144 | Wand of Haste Monster |
| 145 | Wand of Slow Monster |
| 146 | Wand of Confuse Monster |
| 147 | Wand of Sleep Monster |
| 148 | Wand of Drain Life |
| 149 | Wand of Trap/Door Destruction |
| 150 | Wand of Magic Missile |
| 151 | Wand of Wall Building |
| 152 | Wand of Clone Monster |
| 153 | Wand of Teleport Away |
| 154 | Wand of Disarming |
| 155 | Wand of Lightning Balls |
| 156 | Wand of Cold Balls |
| 157 | Wand of Fire Balls |
| 158 | Wand of Stinking Cloud |
| 159 | Wand of Acid Balls |
| 160 | Wand of Wonder |
| 161 | Staff of Light |
| 162 | Staff of Door/Stair Location |
| 163 | Staff of Trap Location |
| 164 | Staff of Treasure Location |
| 165 | Staff of Object Location |
| 166 | Staff of Teleportation |
| 167 | Staff of Earthquakes |
| 168 | Staff of Summoning |
| 169 | Staff of Summoning |
| 170 | Staff of Destruction |
| 171 | Staff of Starlite |
| 172 | Staff of Haste Monsters |
| 173 | Staff of Slow Monsters |
| 174 | Staff of Sleep Monsters |
| 175 | Staff of Cure Light Wounds |
| 176 | Staff of Detect Invisible |
| 177 | Staff of Speed |
| 178 | Staff of Slowness |
| 179 | Staff of Mass Polymorph |
| 180 | Staff of Remove Curse |
| 181 | Staff of Detect Evil |
| 182 | Staff of Curing |
| 183 | Staff of Dispel Evil |
| 184 | Staff of Darkness |
| 185 | Staff of Darkness |
| 186 | Spellbook Beginners-Magick |
| 187 | Spellbook Magick I |
| 188 | Spellbook Magick II |
| 189 | Spellbook The Mages Guide to Power |
| 190 | Holy Book of Prayers Beginners Handbook |
| 191 | Holy Book of Prayers Words of Wisdom |
| 192 | Holy Book of Prayers Chants and Blessings |
| 193 | Holy Book of Prayers Exorcism |
| 194 | Brass Lantern |
| 195 | Wooden Torch |
| 196 | Flask of Oil |
| 197 | Iron Spike |
| 198 | Pick |
| 199 | Shovel |
| 200 | Orcish Pick |
| 201 | Dwarven Pick |
| 202 | Gnomish Shovel |
| 203 | Dwarven Shovel |
| 204 | Small Wooden Chest |
| 205 | Large Wooden Chest |
| 206 | Small Iron Chest |
| 207 | Large Iron Chest |
| 208 | Small Steel Chest |
| 209 | Large Steel Chest |
| 210 | Ruined Chest |
| 211 | Cloak |
| 212 | Robe |
| 213 | Leather Armor |
| 214 | Studded Leather Armor |
| 215 | Hard Leather Armor |
| 216 | Hard Studded Leather |
| 217 | Woven Cord Armor |
| 218 | Soft Leather Ring Mail |
| 219 | Hard Leather Ring Mail |
| 220 | Leather Scale Mail |
| 221 | Filthy Rags |
| 222 | Scale Mail |
| 223 | Chain Mail |
| 224 | Rusty Chain Mail |
| 225 | Double Chain Mail |
| 226 | Augmented Chain Mail |
| 227 | Bar Chain Mail |
| 228 | Metal Brigandine Armor |
| 229 | Laminated Armor |
| 230 | Partial Plate Armor |
| 231 | Metal Lamellar Armor |
| 232 | Plate Mail |
| 233 | Ribbed Plate Armor |
| 234 | Short Bow |
| 235 | Long Bow |
| 236 | Composite Bow |
| 237 | Light Crossbow |
| 238 | Heavy Crossbow |
| 239 | Sling |
| 240 | Arrow |
| 241 | Bolt |
| 242 | Rock |
| 243 | Iron Shot |
| 244 | Soft Leather Cap |
| 245 | Hard Leather Cap |
| 246 | Metal Cap |
| 247 | Iron Helm |
| 248 | Steel Helm |
| 249 | Silver Crown |
| 250 | Golden Crown |
| 251 | Jewel Encrusted Crown |
| 252 | Leather Boots |
| 253 | Soft Leather Boots |
| 254 | Hard Leather Boots |
| 255 | Leather Gloves |
| 256 | Gauntlets |
| 257 | Small Shield |
| 258 | Medium Leather Shield |
| 259 | Large Shield |
| 260 | Small Metal Shield |
| 261 | Medium Metal Shield |
| 262 | Large Metal Shield |
| 263 | Main Gauche |
| 264 | Dagger (Misericorde) |
| 265 | Dagger |
| 266 | Dagger (Bodkin) |
| 267 | Broken Dagger |
| 268 | Backsword |
| 269 | Bastard Sword |
| 270 | Thrusting Sword (Bilbo) |
| 271 | Thrusting Sword (Baselard) |
| 272 | Broad Sword |
| 273 | Two-Handed Sword |
| 274 | Cutlass |
| 275 | Two-Handed Sword (Espadon) |
| 276 | Executioner's Sword |
| 277 | Two-Handed Sword (Flamberge) |
| 278 | Foil |
| 279 | Katana |
| 280 | Long Sword |
| 281 | Two-Handed Sword (No-Dachi) |
| 282 | Rapier |
| 283 | Sabre |
| 284 | Short Sword |
| 285 | Two-Handed Sword (Zweihander) |
| 286 | Broken Sword |
| 287 | Battle Axe (Balestarius) |
| 288 | Ball and Chain |
| 289 | Battle Axe |
| 290 | Broad Axe |
| 291 | Cat-o'-Nine-Tails |
| 292 | Wooden Club |
| 293 | Flail |
| 294 | Two-Handed Great Flail |
| 295 | Morningstar |
| 296 | Mace |
| 297 | War Hammer |
| 298 | Mace (Lead-Filled) |
| 299 | Awl-Pike |
| 300 | Beaked Axe |
| 301 | Fauchard |
| 302 | Glaive |
| 303 | Halberd |
| 304 | Lucerne Hammer |
| 305 | Pike |
| 306 | Spear |
| 307 | Lance |
| 308 | Javelin |
| 309 | Ring of Strength |
| 310 | Ring of Gain Dexterity |
| 311 | Ring of Gain Constitution |
| 312 | Ring of Gain Intelligence |
| 313 | Ring of Speed |
| 314 | Ring of Searching |
| 315 | Ring of Teleportation |
| 316 | Ring of Slow Digestion |
| 317 | Ring of Resist Fire |
| 318 | Ring of Resist Cold |
| 319 | Ring of Feather Falling |
| 320 | Ring of Adornment |
| 321 | Ring of Adornment |
| 322 | Ring of Weakness |
| 323 | Ring of Lordly Protection (Fire) |
| 324 | Ring of Lordly Protection (Acid) |
| 325 | Ring of Lordly Protection (Cold) |
| 326 | Ring of WOE |
| 327 | Ring of Stupidity |
| 328 | Ring of Increase Damage |
| 329 | Ring of Increase To-Hit |
| 330 | Ring of Protection |
| 331 | Ring of Aggravate Monster |
| 332 | Ring of See Invisible |
| 333 | Ring of Sustain Strength |
| 334 | Ring of Sustain Intelligence |
| 335 | Ring of Sustain Wisdom |
| 336 | Ring of Sustain Constitution |
| 337 | Ring of Sustain Dexterity |
| 338 | Ring of Sustain Charisma |
| 339 | Ring of Slaying |
| 340 | Amulet of Adornment |
| 341 | Amulet of Adornment |
| 342 | Amulet of Wisdom |
| 343 | Amulet of Charisma |
| 344 | Amulet of Searching |
| 345 | Amulet of Teleportation |
| 346 | Amulet of Slow Digestion |
| 347 | Amulet of Resist Acid |
| 348 | Amulet of the Magi |
| 349 | Amulet of DOOM |
| 350 | Rat Skeleton |
| 351 | Giant Centipede Skeleton |
| 352 | Empty Bottle |
| 353 | Shards of Pottery |
| 354 | Human Skeleton |
| 355 | Dwarf Skeleton |
| 356 | Elf Skeleton |
| 357 | Gnome Skeleton |
| 358 | Broken Set of Teeth |
| 359 | Large Broken Bone |
| 360 | Broken Stick |

## Source References

- Wizard command dispatch: `core/wizard.s`
- Wizard UI menu: `core/ui_wizard.s`
- Symbolic Item IDs: `platforms/shared/item_catalog/item_ids.s`, `tools/item_ids.py`, `core/item_defs.s`
- Item catalog (full `0-360` VMS spec & generated tables): `platforms/shared/item_catalog/item_catalog_spec.json`, `platforms/shared/item_catalog/item_hot_tables.s`
