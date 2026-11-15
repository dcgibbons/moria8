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
- Item generation: `ITEM 0-369: ` (up to 3 digits)
- Level jump: `DLVL 0-99: `

Feedback:
- Success: `OK`
- Failure: `FAIL`
- Bad numeric input: `BAD`
- Wall walk toggle: `WALL ON` / `WALL OFF`

## Generate Item

Wizard item generation uses item IDs `0-369` (defined in
`platforms/shared/item_catalog/item_catalog_spec.json` and generated into
`item_hot_tables.s` / `ITEM.CAT`; `core/item_tables.s` still stops at `0-156`
until runtime wiring completes). IDs `96-127` are the Phase 3 items — new
potions, scrolls, rings, wands, staves, Mithril armor, and amulets; IDs
`128-134` are the chests — wooden, iron, steel, and ruined; ID `135` is the
Iron Spike; ID `136` is the Scroll of Phase Door; IDs `137-139` are the Long
Bow, Composite Bow and Heavy Crossbow; IDs `140-145` the potions of gain stat;
IDs `146-148` the Rings of Lordly Protection and `149` the Amulet of Resist
Acid; IDs `150-152` the crowns; IDs `153-156` the Wands of Fire Bolts, Drain
Life, Lightning Balls and Acid Balls; and IDs `157-369` append the remaining
VMS Moria 4.8 dungeon & store templates using Base-255 Paged 9-bit IDs (Page 0
`= 0-254`, Page 1 `= 255-369` via `slot_lo = id - 255`, `$FF` empty on both
pages).

Behavior:
- Non-gold items try to go into inventory first
- If inventory is full, they fall back to the floor at the player tile
- Gold always becomes floor gold
- Ammunition (Arrow, Bolt, Rock) comes in a stack of 5-10 (`core/wizard.s`;
  dungeon stacks are 7d6 and store stacks 24)
- Enchantment and ego are rolled as for a floor item at the current dungeon
  level (`roll_enchantment`, `roll_ego_type`): a weapon ego, a resistance
  armour or a crown of the Magi comes only by chance, likelier deeper (a
  crown of the Magi is about 1 in 60 of the enchanted crowns made on DL50)

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
- Launchers: Short Bow `49`, Light Crossbow `50`, Sling `51`, Long Bow `137`,
  Composite Bow `138`, Heavy Crossbow `139`; ammunition: Arrow `52`, Bolt
  `53`, Rock `54`. Wield the launcher, then `SHIFT+F` fires the first
  matching ammunition in the pack.
- Resistance jewellery: Ring of Lordly Protection (Fire) `146`, (Acid) `147`,
  (Cold) `148`; Amulet of Resist Acid `149`. Wear one and check the breath or
  touch damage of its element.
- Crowns: Silver `150`, Golden `151`, Jewel Encrusted `152`.
- Attack wands (VMS): Fire Bolts `153` (6d8), Drain Life `154` (50, not the
  undead), Lightning Balls `155` (24), Acid Balls `156` (40). Aim one at a
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
| 2 | Dagger |
| 3 | Short Sword |
| 4 | Long Sword |
| 5 | Mace |
| 6 | Robe |
| 7 | Leather Armor |
| 8 | Chain Mail |
| 9 | Small Shield |
| 10 | Iron Helm |
| 11 | Leather Gloves |
| 12 | Leather Boots |
| 13 | Wooden Torch |
| 14 | Brass Lantern |
| 15 | Ration of Food |
| 16 | Slime Mold |
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
| 70 | Scimitar |
| 71 | Battle Axe |
| 72 | War Hammer |
| 73 | Morningstar |
| 74 | Spear |
| 75 | Pike |
| 76 | Halberd |
| 77 | Quarterstaff |
| 78 | Large Shield |
| 79 | Hard Leather Armor |
| 80 | Scale Mail |
| 81 | Plate Mail |
| 82 | Cloak |
| 83 | Steel Helm |
| 84 | Gauntlets |
| 85 | Soft Leather Boots |
| 86 | Hard Leather Boots |
| 87 | Metal Cap |
| 88 | Sabre |
| 89 | Cutlass |
| 90 | Tulwar |
| 91 | Katana |
| 92 | Flail |
| 93 | Lucerne Hammer |
| 94 | Broad Axe |
| 95 | Awl-Pike |
| 96 | Potion of Healing |
| 97 | Potion of Restoration |
| 98 | Potion of Resist Heat |
| 99 | Potion of Resist Cold |
| 100 | Potion of Cure Critical Wounds |
| 101 | Scroll of Teleport Level |
| 102 | Scroll of Magic Mapping |
| 103 | Scroll of Object Detection |
| 104 | Scroll of Recharging |
| 105 | Scroll of Rune of Protection |
| 106 | Scroll of Genocide |
| 107 | Scroll of Mass Genocide |
| 108 | Scroll of *Destruction* |
| 109 | Ring of Resist Fire |
| 110 | Ring of Resist Cold |
| 111 | Ring of Speed |
| 112 | Ring of See Invisible |
| 113 | Ring of Slaying |
| 114 | Wand of Slow Monster |
| 115 | Wand of Stone-to-Mud |
| 116 | Wand of Teleport Away |
| 117 | Wand of Fire Balls |
| 118 | Wand of Cold Balls |
| 119 | Staff of Dispel Evil |
| 120 | Staff of Destruction |
| 121 | Staff of Speed |
| 122 | Mithril Chain Mail |
| 123 | Mithril Plate Mail |
| 124 | Amulet of Wisdom |
| 125 | Amulet of the Magi |
| 126 | Potion of Neutralize Poison |
| 127 | Staff of Remove Curse |
| 128 | Small Wooden Chest |
| 129 | Large Wooden Chest |
| 130 | Small Iron Chest |
| 131 | Large Iron Chest |
| 132 | Small Steel Chest |
| 133 | Large Steel Chest |
| 134 | Ruined Chest |
| 135 | Iron Spike |
| 136 | Scroll of Phase Door |
| 137 | Long Bow |
| 138 | Composite Bow |
| 139 | Heavy Crossbow |
| 140 | Potion of Gain Strength |
| 141 | Potion of Gain Intelligence |
| 142 | Potion of Gain Wisdom |
| 143 | Potion of Gain Dexterity |
| 144 | Potion of Gain Constitution |
| 145 | Potion of Charisma |
| 146 | Ring of Lordly Protection (Fire) |
| 147 | Ring of Lordly Protection (Acid) |
| 148 | Ring of Lordly Protection (Cold) |
| 149 | Amulet of Resist Acid |
| 150 | Silver Crown |
| 151 | Golden Crown |
| 152 | Jewel Encrusted Crown |
| 153 | Wand of Fire Bolts |
| 154 | Wand of Drain Life |
| 155 | Wand of Lightning Balls |
| 156 | Wand of Acid Balls |
| 157 | Gnomish Shovel |
| 158 | Orcish Pick |
| 159 | Dwarven Shovel |
| 160 | Dwarven Pick |
| 161 | Soft Leather Cap |
| 162 | Hard Leather Cap |
| 163 | Medium Leather Shield |
| 164 | Small Metal Shield |
| 165 | Medium Metal Shield |
| 166 | Large Metal Shield |
| 167 | Filthy Rags |
| 168 | Woven Cord Armor |
| 169 | Hard Studded Leather |
| 170 | Soft Leather Ring Mail |
| 171 | Hard Leather Ring Mail |
| 172 | Leather Scale Mail |
| 173 | Rusty Chain Mail |
| 174 | Double Chain Mail |
| 175 | Augmented Chain Mail |
| 176 | Bar Chain Mail |
| 177 | Metal Brigandine Armor |
| 178 | Laminated Armor |
| 179 | Partial Plate Armor |
| 180 | Metal Lamellar Armor |
| 181 | Ribbed Plate Armor |
| 182 | Broken Dagger |
| 183 | Broken Sword |
| 184 | Wooden Club |
| 185 | Dagger (Misericorde) |
| 186 | Dagger (Bodkin) |
| 187 | Foil |
| 188 | Iron Shot |
| 189 | Cat-o'-Nine-Tails |
| 190 | Javelin |
| 191 | Thrusting Sword (Bilbo) |
| 192 | Thrusting Sword (Baselard) |
| 193 | Backsword |
| 194 | Lance |
| 195 | Beaked Axe |
| 196 | Mace (Lead-Filled) |
| 197 | Fauchard |
| 198 | Ball and Chain |
| 199 | Glaive |
| 200 | Battle Axe (Balestarius) |
| 201 | Two-Handed Sword (Espadon) |
| 202 | Executioner's Sword |
| 203 | Two-Handed Great Flail |
| 204 | Two-Handed Sword (No-Dachi) |
| 205 | Two-Handed Sword (Flamberge) |
| 206 | Two-Handed Sword (Zweihander) |
| 207 | Amulet of Teleportation |
| 208 | Amulet of Slow Digestion |
| 209 | Amulet of Searching |
| 210 | Amulet of Adornment |
| 211 | Amulet of Adornment |
| 212 | Amulet of Charisma |
| 213 | Amulet of DOOM |
| 214 | Copper |
| 215 | Copper |
| 216 | Copper |
| 217 | Silver |
| 218 | Silver |
| 219 | Silver |
| 220 | Garnets |
| 221 | Garnets |
| 222 | Gold |
| 223 | Gold |
| 224 | Gold |
| 225 | Opals |
| 226 | Sapphires |
| 227 | Gold |
| 228 | Rubies |
| 229 | Diamonds |
| 230 | Emeralds |
| 231 | Mithril |
| 232 | Empty Bottle |
| 233 | Shards of Pottery |
| 234 | Broken Set of Teeth |
| 235 | Large Broken Bone |
| 236 | Broken Stick |
| 237 | Rat Skeleton |
| 238 | Giant Centipede Skeleton |
| 239 | Human Skeleton |
| 240 | Dwarf Skeleton |
| 241 | Elf Skeleton |
| 242 | Gnome Skeleton |
| 243 | Hard Biscuit |
| 244 | Pint of Fine Ale |
| 245 | Strip of Beef Jerky |
| 246 | Pint of Fine Wine |
| 247 | Pint of Fine Grade Mush |
| 248 | Mushroom of First-Aid |
| 249 | Piece of Elvish Waybread |
| 250 | Mushroom of Cure Confusion |
| 251 | Mushroom of Poison |
| 252 | Mushroom of Confusion |
| 253 | Mushroom of Weakness |
| 254 | Mushroom of Minor Cures |
| 255 | Mushroom of Cure Poison |
| 256 | Mushroom of Blindness |
| 257 | Mushroom of Paranoia |
| 258 | Mushroom of Light Cures |
| 259 | Mushroom of Cure Blindness |
| 260 | Mushroom of Cure Paranoia |
| 261 | Mushroom of Hallucination |
| 262 | Hairy Mold of Poison |
| 263 | Mushroom of Unhealth |
| 264 | Hairy Mold of Cure Serious Wounds |
| 265 | Hairy Mold of Hallucinations |
| 266 | Hairy Mold of Cure Poison |
| 267 | Mushroom of Restore Constitution |
| 268 | Hairy Mold of Unhealth |
| 269 | Mushroom of Restoring |
| 270 | Potion of Sleep |
| 271 | Clear Potion of Water |
| 272 | Potion of Salt Water |
| 273 | Light Brown Potion of Apple Juice |
| 274 | Icky Green Potion of Slime Mold Juice |
| 275 | Potion of Slowness |
| 276 | Potion of Boldness |
| 277 | Potion of Slow Poison |
| 278 | Potion of Weakness |
| 279 | Potion of Detect Invisible |
| 280 | Potion of Super Heroism |
| 281 | Potion of Lose Memories |
| 282 | Potion of Lose Intelligence |
| 283 | Potion of Lose Wisdom |
| 284 | Potion of Ugliness |
| 285 | Potion of Invulnerability |
| 286 | Potion of Restore Strength |
| 287 | Potion of Restore Intelligence |
| 288 | Potion of Restore Wisdom |
| 289 | Potion of Restore Charisma |
| 290 | Potion of Restore Dexterity |
| 291 | Potion of Restore Constitution |
| 292 | Potion of Restore Life Levels |
| 293 | Potion of Learning |
| 294 | Potion of Gain Experience |
| 295 | Scroll of Treasure Detection |
| 296 | Scroll of Summon Monster |
| 297 | Scroll of Darkness |
| 298 | Scroll of Blessing |
| 299 | Scroll of Detect Invisible |
| 300 | Scroll of Create Food |
| 301 | Scroll of Sleep Monster |
| 302 | Scroll of Trap Detection |
| 303 | Scroll of Door/Stair Location |
| 304 | Scroll of Trap Creation |
| 305 | Scroll of Holy Chant |
| 306 | Scroll of Trap/Door Destruction |
| 307 | Scroll of Door Creation |
| 308 | Scroll of Enchant Weapon To-Hit |
| 309 | Scroll of Enchant Weapon To-Dam |
| 310 | Scroll of Summon Undead |
| 311 | Scroll of Holy Prayer |
| 312 | Scroll of Dispel Undead |
| 313 | Scroll of Curse Weapon |
| 314 | Scroll of Curse Armor |
| 315 | Scroll of *Enchant Weapon* |
| 316 | Scroll of *Enchant Armor* |
| 317 | Ring of Teleportation |
| 318 | Ring of Weakness |
| 319 | Ring of Aggravate Monster |
| 320 | Ring of Adornment |
| 321 | Ring of Adornment |
| 322 | Ring of Feather Falling |
| 323 | Ring of Searching |
| 324 | Ring of Slow Digestion |
| 325 | Ring of Sustain Charisma |
| 326 | Ring of Stupidity |
| 327 | Ring of Increase Damage |
| 328 | Ring of Increase To-Hit |
| 329 | Ring of Gain Intelligence |
| 330 | Ring of Gain Dexterity |
| 331 | Ring of Gain Constitution |
| 332 | Ring of Sustain Intelligence |
| 333 | Ring of Sustain Wisdom |
| 334 | Ring of Sustain Strength |
| 335 | Ring of Sustain Constitution |
| 336 | Ring of Sustain Dexterity |
| 337 | Ring of WOE |
| 338 | Wand of Heal Monster |
| 339 | Wand of Haste Monster |
| 340 | Wand of Clone Monster |
| 341 | Wand of Magic Missile |
| 342 | Wand of Wonder |
| 343 | Wand of Confuse Monster |
| 344 | Wand of Sleep Monster |
| 345 | Wand of Trap/Door Destruction |
| 346 | Wand of Polymorph |
| 347 | Wand of Disarming |
| 348 | Wand of Wall Building |
| 349 | Staff of Treasure Location |
| 350 | Staff of Object Location |
| 351 | Staff of Detect Invisible |
| 352 | Staff of Summoning |
| 353 | Staff of Haste Monsters |
| 354 | Staff of Door/Stair Location |
| 355 | Staff of Trap Location |
| 356 | Staff of Sleep Monsters |
| 357 | Staff of Slow Monsters |
| 358 | Staff of Detect Evil |
| 359 | Staff of Starlite |
| 360 | Staff of Curing |
| 361 | Staff of Slowness |
| 362 | Staff of Earthquakes |
| 363 | Staff of Mass Polymorph |
| 364 | Staff of Darkness |
| 365 | Piece of Elvish Waybread |
| 366 | Scroll of Trap Detection |
| 367 | Scroll of Door/Stair Location |
| 368 | Staff of Summoning |
| 369 | Staff of Darkness |

## Source References

- Wizard command dispatch: `core/wizard.s`
- Wizard UI menu: `core/ui_wizard.s`
- Item IDs (core runtime): `core/item_tables.s`
- Item catalog (full `0-369` spec & generated tables): `platforms/shared/item_catalog/item_catalog_spec.json`, `platforms/shared/item_catalog/item_hot_tables.s`
