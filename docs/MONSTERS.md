# Moria8 Monster Reference

The Commodore releases ship a selected monster roster, not the full Umoria
creature catalog. The current shipped set contains 120 selected creatures from
Umoria's 279-creature catalog, arranged into overlapping active tiers for the
Commodore memory model.

The tier tables below list what can be loaded by the current game. Some
creatures appear in more than one tier so transitions between depth bands can
stay smooth. Dungeon level (`DL`) is the depth associated with the creature in
the shipped data.

Monster recall display exists, but persistent recall is not complete in the
current Commodore builds.

## How To Read Monsters

Moria8 tracks these shipped monster fields:

- Tier: active creature data group. C64 loads these from disk or REU, Plus/4
  loads them from disk, and C128 caches them through its banked model.
- DL: native dungeon level. Deeper monsters are generally more dangerous.
- Speed: slow, normal, or fast. Fast monsters can act more often.
- HD: hit dice. More and larger dice mean more hit points.
- AC: armor class. Higher AC is harder to hit.
- Sleep: how asleep or alert the creature starts. Lower values wake more
  readily.
- AAF: awareness radius. Higher values notice the player from farther away.
- XP: experience award.
- Attacks: up to two compact melee attacks in the current shipped table.
- Spells: spell chance and spell flags for casters, breathers, and special
  monsters.

Practical reading: if it is fast, deep, high-HP, spellcasting, breath-capable,
or status-heavy, treat it as dangerous until proven otherwise.

## Town Tier

Town creatures are level 0 and are always resident. Dungeon creature rows start
empty at boot and are populated from the generated tier data when a dungeon
tier is activated.

| DL | Creature |
| ---: | -------- |
| 0 | Filthy Street Urchin |
| 0 | Blubbering Idiot |
| 0 | Pitiful-Looking Beggar |
| 0 | Mangy-Looking Leper |
| 0 | Squint-Eyed Rogue |
| 0 | Singing, Happy Drunk |
| 0 | Mean-Looking Mercenary |
| 0 | Battle-Scarred Veteran |

## Tier 1: Shallow Dungeon

Tier 1 covers DL 1-8.

| DL | Creature |
| ---: | -------- |
| 1 | Kobold |
| 1 | White Worm mass |
| 1 | Floating Eye |
| 2 | Novice Priest |
| 2 | Novice Mage |
| 2 | Giant Black Ant |
| 3 | Poltergeist |
| 3 | Black Naga |
| 3 | Yellow Jelly |
| 4 | Creeping Copper Coins |
| 4 | Blue Worm mass |
| 4 | Jackal |
| 5 | Green Naga |
| 5 | White Mushroom patch |
| 5 | Skeleton Kobold |
| 6 | Brown Mold |
| 6 | Orc |
| 6 | Rattlesnake |
| 7 | Bloodshot Eye |
| 7 | Zombie Kobold |
| 7 | Lost Soul |
| 8 | Green Mold |
| 8 | Skeleton Orc |
| 8 | Bandit |

## Tier 2: Early Dungeon

Tier 2 covers DL 5-15.

| DL | Creature |
| ---: | -------- |
| 5 | Green Naga |
| 5 | White Mushroom patch |
| 5 | Skeleton Kobold |
| 6 | Brown Mold |
| 6 | Orc |
| 6 | Rattlesnake |
| 7 | Bloodshot Eye |
| 7 | Zombie Kobold |
| 7 | Lost Soul |
| 8 | Green Mold |
| 8 | Skeleton Orc |
| 8 | Bandit |
| 9 | Orc Shaman |
| 9 | Giant Red Ant |
| 9 | King Cobra |
| 10 | Giant White Tick |
| 10 | Disenchanter Mold |
| 10 | Creeping Gold Coins |
| 11 | Orc Zombie |
| 11 | Nasty Little Gnome |
| 11 | Hobgoblin |
| 12 | Black Mamba |
| 12 | Priest |
| 12 | Skeleton Human |
| 13 | Ogre |
| 13 | Magic User |
| 13 | Black Orc |
| 14 | Giant White Dragon Fly |
| 14 | Hill Giant |
| 14 | Flesh Golem |
| 15 | Frost Giant |
| 15 | Violet Mold |

## Tier 3: Mid Dungeon

Tier 3 covers DL 11-25.

| DL | Creature |
| ---: | -------- |
| 11 | Orc Zombie |
| 11 | Nasty Little Gnome |
| 11 | Hobgoblin |
| 12 | Black Mamba |
| 12 | Priest |
| 12 | Skeleton Human |
| 13 | Ogre |
| 13 | Magic User |
| 13 | Black Orc |
| 14 | Giant White Dragon Fly |
| 14 | Hill Giant |
| 14 | Flesh Golem |
| 15 | Frost Giant |
| 15 | Violet Mold |
| 16 | Umber Hulk |
| 16 | Fire Giant |
| 16 | Quasit |
| 17 | Troll |
| 17 | Giant Brown Scorpion |
| 17 | Earth Spirit |
| 18 | Fire Spirit |
| 18 | Uruk-Hai Orc |
| 18 | Stone Giant |
| 19 | Stone Golem |
| 19 | Killer Black Beetle |
| 20 | Quylthulg |
| 20 | Cloud Giant |
| 21 | Mummified Orc |
| 21 | Killer Boring Beetle |
| 22 | Killer Stag Beetle |
| 22 | Iron Golem |
| 22 | Giant Yellow Scorpion |
| 23 | Warrior |
| 23 | Giant Silver Ant |
| 24 | Forest Wight |
| 24 | Mummified Human |
| 24 | Banshee |
| 25 | Giant Troll |
| 25 | Killer Red Beetle |

## Tier 4: Deep Dungeon

Tier 4 covers DL 20-100.

| DL | Creature |
| ---: | -------- |
| 20 | Quylthulg |
| 20 | Cloud Giant |
| 21 | Mummified Orc |
| 21 | Killer Boring Beetle |
| 22 | Killer Stag Beetle |
| 22 | Iron Golem |
| 22 | Giant Yellow Scorpion |
| 23 | Warrior |
| 23 | Giant Silver Ant |
| 24 | Forest Wight |
| 24 | Mummified Human |
| 24 | Banshee |
| 25 | Giant Troll |
| 25 | Killer Red Beetle |
| 26 | Giant Fire Tick |
| 26 | White Wraith |
| 26 | Giant Black Scorpion |
| 27 | Killer Fire Beetle |
| 27 | Vampire |
| 27 | Shimmering Mold |
| 28 | Black Knight |
| 28 | Mage |
| 28 | Ice Troll |
| 29 | Giant Purple Worm |
| 29 | Young Blue Dragon |
| 29 | Young Green Dragon |
| 30 | Skeleton Troll |
| 30 | Grave Wight |
| 31 | Ghost |
| 31 | Death Watch Beetle |
| 31 | Ogre Mage |
| 32 | Two-Headed Troll |
| 32 | Invisible Stalker |
| 32 | Ninja |
| 33 | Barrow Wight |
| 33 | Fire Elemental |
| 34 | Lich |
| 34 | Master Vampire |
| 34 | Earth Elemental |
| 35 | Young Red Dragon |
| 35 | Necromancer |
| 35 | Mature White Dragon |
| 36 | Xorn |
| 36 | Grey Wraith |
| 37 | Iridescent Beetle |
| 37 | King Lich |
| 37 | Mature Red Dragon |
| 38 | Ancient White Dragon |
| 38 | Black Wraith |
| 39 | Nether Wraith |
| 39 | Sorcerer |
| 39 | Ancient Blue Dragon |
| 40 | Ancient Red Dragon |
| 40 | Emperor Lich |
| 40 | Ancient Multi-Hued Dragon |
| 50 | Evil Iggy |
| 100 | Balrog |

## Threat Notes

These are deliberately light-spoiler notes for players who want to survive
without memorizing every numeric field.

- Floating Eyes and similar passive-looking creatures can still be dangerous;
  inspect unfamiliar letters before walking into them.
- Molds, jellies, eyes, ghosts, wights, vampires, and liches often matter more
  for special effects than raw melee damage.
- Fast monsters are disproportionately dangerous because they can erase your
  retreat margin.
- Casters such as priests, mages, ogre mages, necromancers, sorcerers, liches,
  and high undead should be fought with escape options ready.
- Dragon breath is the classic deep-dungeon spike damage. Do not give mature or
  ancient dragons free turns at range unless you can survive the breath.
- The Balrog is the endgame target. It is not just another deep monster; prepare
  for fire, heavy damage, and a long fight.

## Deep Threat Stats

These are exact shipped tier-4 values for the obvious breath/endgame threats.
`Sp%` is the monster spell/breath chance field. `XP` is the experience award.

| DL | Creature | Speed | HD | AC | XP | Sp% |
| ---: | -------- | ----- | --- | ---: | ---: | ---: |
| 29 | Young Blue Dragon | Normal | 33d8 | 50 | 300 | 9 |
| 29 | Young Green Dragon | Normal | 32d8 | 50 | 290 | 9 |
| 35 | Young Red Dragon | Normal | 36d8 | 60 | 650 | 10 |
| 35 | Mature White Dragon | Normal | 48d8 | 65 | 1000 | 10 |
| 37 | Mature Red Dragon | Normal | 60d8 | 80 | 1400 | 12 |
| 38 | Ancient White Dragon | Fast | 88d8 | 80 | 1500 | 11 |
| 39 | Ancient Blue Dragon | Fast | 87d8 | 90 | 2500 | 12 |
| 40 | Ancient Red Dragon | Fast | 105d8 | 100 | 2750 | 16 |
| 40 | Ancient Multi-Hued Dragon | Fast | 52d40 | 100 | 12000 | 20 |
| 50 | Evil Iggy | Fast | 60d40 | 80 | 18000 | 33 |
| 100 | Balrog | Fast | 75d40 | 125 | 55000 | 33 |

## Current Limits

Moria8 uses the shipped tier roster above. Full Umoria creature breadth,
stable global creature IDs for every upstream monster, and complete persistent
monster recall remain future work. Monster attacks and spells use the compact
shipped implementation; several upstream special attacks and content effects
are not implemented yet.

The creature data now imports Umoria's infravision visibility bit for warm
monsters. C64, C128, and Plus/4 render those monsters through player
infravision in darkness without revealing the underlying map.
