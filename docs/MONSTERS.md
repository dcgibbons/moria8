# Moria8 Monster Reference

All eight Moria8 ports (Commodore 64, Commodore 128, Plus/4, Apple IIe, Commander X16, Atari 8-bit, BBC Master 128, and CP/M 2.2 Z80 *(in progress)*) and all five shipping cartridges (`moria8-c64.crt`, `moria8-c128.crt`, `moria8-plus4.crt`, `moria8-cx16.crt`, `moria8-atari8.car`) ship the full **279-species** VMS Moria 4.8 monster catalog (`platforms/shared/catalog/monster_catalog_spec.json`).

Species are ordered natively by dungeon level (`DL 0–100`) and backed per platform via disk, `MORIA8.DAT` (`BDOS 33` on CP/M), banked/auxiliary RAM, REU, or cartridge ROM (`29` SoA/record bytes per species plus variable-length Huffman/screen-code or pure ASCII names). Town species (`#0–#7`, `DL 0`) stay resident at town slots, while dungeon monsters (`#8–#278`) are paged into active level tables as needed and inspected in full via Monster Recall (`/`).

## How To Read Monsters

Moria8 tracks 29 packed fields per species (`21` core fields + `8` Phase 5 extended fields):

- **Catalog ID (`#0–#278`) & `DL`**: Stable index in `monster_catalog_spec.json` and native dungeon depth.
- **Speed**: `Slow` (acts on even turns), `Normal` (1 action/turn), or `Fast` (extra actions/turn), plus upstream `CM_20/40/75_RANDOM` erratic movement flags.
- **HD**: Hit dice (`NdS`). Species with `CD_MAX_HP` (`41` in all, including Quylthulgs, mature/ancient dragons, greater undead, Evil Iggy, and the Balrog) always spawn with maximum `N * S` hit points (up to the Balrog's `125d24` = `3,000` HP).
- **AC / Sleep / AAF / XP**: Armor class, initial sleep timer (`0` = always awake), Area Awareness Factor (`1–127` tiles + `CD_OPEN_DOOR`), and 16-bit XP award.
- **Attacks (`atk0..atk3`)**: Up to **4** melee attack slots with 19 VMS verbs (`ADESC_*`) and all 24 effect types (`ATK_*`: normal damage, stat drains, elemental touches, acid/corrosion, fear, blindness, confusion, paralysis, gold/item theft, EXP drain, aggravate, disenchant, and eating food/light/charges).
- **Spells & Breath (`spell_chance`, `spell_flags`, `spell_flags2`)**: 1-in-N cast frequency (`MS_FREQ_MASK`), 6 breath element encodings, `Hold Person`, 8 primary spell flags (`CLW`, `Breath`, `Summon`, `Teleport-To`, `Blind`, `Confuse`, `CSW`, `Fear`), and 5 extended spells (`Blink`, `Teleport Self`, `Summon Undead`, `Slow Person`, `Drain Mana`), plus `CM2_PHASE`, `CM2_EATS_OTHER`, and `CM2_PICKS_UP`.
- **Defenses & Traits (`cdefense`, `mflags`)**: Elemental/stone vulnerabilities (`FIR`, `CLD`, `ACD`, `PSN`, `LIT`, `STN`), `CD_NO_SLEEP`, `CD_INVISIBLE`, `CF_UNDEAD`, `CF_EVIL`, `CF_ANIMAL`, `CF_DRAGON`, `CF_BREEDER`, `CF_ATTACK_ONLY`, and `CF_INFRA` (visible via infravision in darkness on all 8 ports).

You can also search, filter, and simulate encounters and Phase 5 recall screens interactively in the [Monster Compendium](monsters.html).

## Town (DL 0)

Town creatures are level 0 and are always active in the town roster. (8 species.)

| # | DL | Glyph | Creature | HD | AC | XP |
| ---: | ---: | :---: | -------- | --- | ---: | ---: |
| 0 | 0 | `p` | Filthy Street Urchin | 1d4 | 1 | 0 |
| 1 | 0 | `p` | Blubbering Idiot | 1d2 | 1 | 0 |
| 2 | 0 | `p` | Pitiful Looking Beggar | 1d4 | 1 | 0 |
| 3 | 0 | `p` | Mangy Looking Leper | 1d1 | 1 | 0 |
| 4 | 0 | `p` | Squint Eyed Rogue | 2d8 | 8 | 0 |
| 5 | 0 | `p` | Singing, Happy Drunk | 2d3 | 1 | 0 |
| 6 | 0 | `p` | Mean Looking Mercenary | 5d8 | 20 | 0 |
| 7 | 0 | `p` | Battle Scarred Veteran | 7d8 | 30 | 0 |

## Band 1: Shallow Dungeon (DL 1–8)

88 native species spawning across dungeon levels 1–8. (88 species.)

| # | DL | Glyph | Creature | HD | AC | XP |
| ---: | ---: | :---: | -------- | --- | ---: | ---: |
| 8 | 1 | `,` | Grey Mushroom patch | 1d2 | 1 | 1 |
| 9 | 1 | `c` | Giant Yellow Centipede | 2d6 | 12 | 2 |
| 10 | 1 | `c` | Giant White Centipede | 3d5 | 10 | 2 |
| 11 | 1 | `i` | White Icky-Thing | 3d5 | 7 | 2 |
| 12 | 1 | `i` | Clear Icky-Thing | 2d5 | 6 | 1 |
| 13 | 1 | `r` | Giant White Mouse | 1d3 | 4 | 1 |
| 14 | 1 | `R` | Large Brown Snake | 4d6 | 35 | 3 |
| 15 | 1 | `R` | Large White Snake | 3d6 | 30 | 2 |
| 16 | 1 | `k` | Kobold | 3d7 | 16 | 5 |
| 17 | 1 | `w` | White Worm mass | 4d4 | 1 | 2 |
| 18 | 1 | `e` | Floating Eye | 3d6 | 6 | 1 |
| 19 | 2 | `,` | Shrieker Mushroom patch | 1d1 | 1 | 1 |
| 20 | 2 | `i` | Blubbering Icky-Thing | 5d8 | 4 | 8 |
| 21 | 2 | `c` | Metallic Green Centipedes | 4d4 | 4 | 3 |
| 22 | 2 | `p` | Novice Warrior | 9d4 | 16 | 6 |
| 23 | 2 | `p` | Novice Rogue | 8d4 | 12 | 6 |
| 24 | 2 | `p` | Novice Priest | 7d4 | 10 | 7 |
| 25 | 2 | `p` | Novice Mage | 6d4 | 6 | 7 |
| 26 | 2 | `,` | Yellow Mushroom patch | 1d1 | 1 | 2 |
| 27 | 2 | `J` | White Jelly | 8d8 | 1 | 10 |
| 28 | 2 | `f` | Giant Green Frog | 2d8 | 8 | 6 |
| 29 | 2 | `a` | Giant Black Ant | 3d6 | 20 | 8 |
| 30 | 2 | `h` | White Harpy | 2d5 | 17 | 5 |
| 31 | 2 | `y` | Blue Yeek | 2d6 | 14 | 4 |
| 32 | 2 | `w` | Green Worm mass | 6d4 | 3 | 3 |
| 33 | 2 | `R` | Large Black Snake | 4d8 | 38 | 9 |
| 34 | 3 | `G` | Poltergeist | 2d5 | 15 | 6 |
| 35 | 3 | `c` | Metallic Blue Centipedes | 4d5 | 6 | 7 |
| 36 | 3 | `l` | Giant White Louse | 1d1 | 5 | 1 |
| 37 | 3 | `n` | Black Naga | 6d8 | 40 | 20 |
| 38 | 3 | `,` | Spotted Mushroom patch | 1d1 | 1 | 3 |
| 39 | 3 | `J` | Yellow Jelly | 10d8 | 1 | 12 |
| 40 | 3 | `p` | Scruffy looking Hobbit | 3d5 | 8 | 4 |
| 41 | 3 | `b` | Huge Brown Bat | 2d6 | 12 | 4 |
| 42 | 3 | `a` | Giant White Ant | 3d6 | 16 | 7 |
| 43 | 3 | `m` | Yellow Mold | 8d8 | 10 | 9 |
| 44 | 3 | `c` | Metallic Red Centipedes | 4d8 | 9 | 12 |
| 45 | 3 | `w` | Yellow Worm mass | 4d8 | 4 | 4 |
| 46 | 3 | `R` | Large Green Snake | 6d8 | 40 | 10 |
| 47 | 3 | `e` | Radiation Eye | 3d6 | 6 | 6 |
| 48 | 3 | `h` | Drooling Harpy | 2d8 | 22 | 7 |
| 49 | 4 | `r` | Silver Mouse | 1d1 | 5 | 1 |
| 50 | 4 | `,` | Black Mushroom patch | 8d8 | 1 | 8 |
| 51 | 4 | `J` | Blue Jelly | 12d8 | 1 | 14 |
| 52 | 4 | `$` | Creeping Copper Coins | 7d8 | 24 | 9 |
| 53 | 4 | `r` | Giant White Rat | 2d2 | 7 | 1 |
| 54 | 4 | `c` | Giant Black Centipede | 5d8 | 20 | 11 |
| 55 | 4 | `c` | Giant Blue Centipede | 4d8 | 20 | 10 |
| 56 | 4 | `w` | Blue Worm mass | 5d8 | 12 | 5 |
| 57 | 4 | `R` | Large Green Snake | 6d8 | 41 | 14 |
| 58 | 4 | `j` | Jackal | 3d8 | 16 | 8 |
| 59 | 5 | `n` | Green Naga | 9d8 | 40 | 30 |
| 60 | 5 | `G` | Green Glutton Ghost | 3d6 | 20 | 15 |
| 61 | 5 | `,` | White Mushroom patch | 1d1 | 1 | 5 |
| 62 | 5 | `J` | Green Jelly | 22d8 | 1 | 18 |
| 63 | 5 | `s` | Skeleton Kobold | 5d8 | 26 | 12 |
| 64 | 5 | `J` | Silver Jelly | 20d8 | 25 | 15 |
| 65 | 5 | `f` | Giant Black Frog | 4d8 | 18 | 12 |
| 66 | 5 | `i` | Grey Icky-Thing | 4d8 | 12 | 10 |
| 67 | 5 | `e` | Disenchanter Eye | 7d8 | 10 | 20 |
| 68 | 5 | `y` | Black Yeek | 2d8 | 16 | 8 |
| 69 | 5 | `w` | Red Worm mass | 5d8 | 12 | 6 |
| 70 | 5 | `F` | Giant House Fly | 3d8 | 16 | 10 |
| 71 | 5 | `R` | Copperhead Snake | 4d6 | 20 | 15 |
| 72 | 5 | `J` | Rot Jelly | 20d8 | 30 | 15 |
| 73 | 6 | `,` | Purple Mushroom patch | 1d1 | 1 | 12 |
| 74 | 6 | `m` | Brown Mold | 15d8 | 12 | 20 |
| 75 | 6 | `b` | Giant Brown Bat | 3d8 | 15 | 10 |
| 76 | 6 | `$` | Creeping Silver Coins | 12d8 | 30 | 18 |
| 77 | 6 | `o` | Orc | 9d8 | 32 | 16 |
| 78 | 6 | `h` | Grey Harpy | 3d8 | 20 | 14 |
| 79 | 6 | `i` | Blue Icky-Thing | 4d8 | 14 | 12 |
| 80 | 6 | `R` | Rattlesnake | 6d7 | 24 | 20 |
| 81 | 7 | `e` | Bloodshot Eye | 4d8 | 6 | 15 |
| 82 | 7 | `n` | Red Naga | 11d8 | 40 | 40 |
| 83 | 7 | `J` | Red Jelly | 26d8 | 1 | 26 |
| 84 | 7 | `f` | Giant Red Frog | 5d8 | 16 | 16 |
| 85 | 7 | `i` | Green Icky-Thing | 5d8 | 12 | 18 |
| 86 | 7 | `z` | Zombie Kobold | 6d8 | 14 | 14 |
| 87 | 7 | `G` | Lost Soul | 2d8 | 10 | 18 |
| 88 | 7 | `p` | Greedy little Gnome | 3d8 | 14 | 13 |
| 89 | 7 | `F` | Giant Green Fly | 3d8 | 14 | 15 |
| 90 | 8 | `y` | Brown Yeek | 3d8 | 18 | 11 |
| 91 | 8 | `m` | Green Mold | 21d8 | 14 | 28 |
| 92 | 8 | `s` | Skeleton Orc | 10d8 | 36 | 26 |
| 93 | 8 | `p` | Seedy looking Human | 8d8 | 26 | 22 |
| 94 | 8 | `i` | Red Icky-Thing | 4d8 | 18 | 22 |
| 95 | 8 | `p` | Bandit | 8d8 | 24 | 26 |

## Band 2: Early Dungeon (DL 9–15)

57 native species spawning across dungeon levels 9–15. (57 species.)

| # | DL | Glyph | Creature | HD | AC | XP |
| ---: | ---: | :---: | -------- | --- | ---: | ---: |
| 96 | 9 | `Y` | Yeti | 11d8 | 24 | 30 |
| 97 | 9 | `i` | Bloodshot Icky-Thing | 7d8 | 18 | 24 |
| 98 | 9 | `r` | Giant Grey Rat | 2d3 | 12 | 2 |
| 99 | 9 | `h` | Black Harpy | 3d8 | 22 | 19 |
| 100 | 9 | `b` | Giant Black Bat | 2d8 | 18 | 16 |
| 101 | 9 | `y` | Clear Yeek | 3d6 | 24 | 14 |
| 102 | 9 | `o` | Orc Shaman | 7d8 | 15 | 30 |
| 103 | 9 | `a` | Giant Red Ant | 4d8 | 34 | 22 |
| 104 | 9 | `R` | King Cobra | 8d8 | 30 | 28 |
| 105 | 10 | `,` | Clear Mushroom patch | 1d1 | 1 | 1 |
| 106 | 10 | `t` | Giant White Tick | 15d8 | 40 | 27 |
| 107 | 10 | `m` | Hairy Mold | 15d8 | 15 | 32 |
| 108 | 10 | `m` | Disenchanter Mold | 16d8 | 20 | 40 |
| 109 | 10 | `c` | Giant Red Centipede | 3d8 | 26 | 24 |
| 110 | 10 | `$` | Creeping Gold Coins | 18d8 | 36 | 32 |
| 111 | 10 | `F` | Giant Fruit Fly | 2d2 | 14 | 4 |
| 112 | 10 | `p` | Brigand | 9d8 | 32 | 35 |
| 113 | 11 | `z` | Orc Zombie | 11d8 | 24 | 30 |
| 114 | 11 | `o` | Orc Warrior | 11d8 | 36 | 34 |
| 115 | 11 | `r` | Vorpal Bunny | 2d3 | 10 | 2 |
| 116 | 11 | `p` | Nasty little Gnome | 4d8 | 10 | 32 |
| 117 | 11 | `H` | Hobgoblin | 12d8 | 38 | 38 |
| 118 | 12 | `R` | Black Mamba | 10d8 | 32 | 40 |
| 119 | 12 | `J` | Grape Jelly | 52d8 | 1 | 60 |
| 120 | 12 | `y` | Master Yeek | 5d8 | 24 | 28 |
| 121 | 12 | `p` | Priest | 7d8 | 22 | 36 |
| 122 | 12 | `a` | Giant Clear Ant | 3d7 | 18 | 24 |
| 123 | 12 | `E` | Air Spirit | 5d8 | 20 | 40 |
| 124 | 12 | `s` | Skeleton Human | 12d8 | 30 | 38 |
| 125 | 12 | `z` | Human Zombie | 11d8 | 24 | 34 |
| 126 | 12 | `G` | Moaning Spirit | 4d8 | 20 | 44 |
| 127 | 12 | `p` | Swordsman | 11d8 | 34 | 40 |
| 128 | 13 | `K` | Killer Brown Beetle | 13d8 | 40 | 38 |
| 129 | 13 | `o` | Ogre | 13d8 | 32 | 42 |
| 130 | 13 | `f` | Giant Red Speckled Frog | 6d8 | 20 | 32 |
| 131 | 13 | `p` | Magic User | 7d8 | 10 | 35 |
| 132 | 13 | `o` | Black Orc | 12d8 | 36 | 40 |
| 133 | 13 | `b` | Giant Long-Eared Bat | 5d8 | 20 | 20 |
| 134 | 13 | `F` | Giant Gnat | 1d2 | 4 | 1 |
| 135 | 14 | `K` | Killer Green Beetle | 16d8 | 45 | 46 |
| 136 | 14 | `F` | Giant Flea | 2d2 | 25 | 1 |
| 137 | 14 | `F` | Giant White Dragon Fly | 5d8 | 20 | 54 |
| 138 | 14 | `P` | Hill Giant | 16d8 | 36 | 52 |
| 139 | 14 | `s` | Skeleton Hobgoblin | 13d8 | 34 | 46 |
| 140 | 14 | `g` | Flesh Golem | 12d8 | 10 | 48 |
| 141 | 14 | `b` | White Dragon Bat | 2d6 | 20 | 40 |
| 142 | 14 | `l` | Giant Black Louse | 1d1 | 7 | 1 |
| 143 | 15 | `n` | Guardian Naga | 24d8 | 50 | 60 |
| 144 | 15 | `b` | Giant Grey Bat | 4d8 | 22 | 22 |
| 145 | 15 | `c` | Giant Clear Centipede | 5d8 | 30 | 30 |
| 146 | 15 | `t` | Giant Yellow Tick | 20d8 | 48 | 48 |
| 147 | 15 | `a` | Giant Ebony Ant | 3d4 | 24 | 3 |
| 148 | 15 | `P` | Frost Giant | 17d8 | 38 | 54 |
| 149 | 15 | `g` | Clay Golem | 14d8 | 20 | 50 |
| 150 | 15 | `b` | Huge White Bat | 3d8 | 12 | 3 |
| 151 | 15 | `b` | Giant Tan Bat | 3d8 | 18 | 18 |
| 152 | 15 | `m` | Violet Mold | 17d8 | 15 | 50 |

## Band 3: Mid Dungeon (DL 16–25)

49 native species spawning across dungeon levels 16–25. (49 species.)

| # | DL | Glyph | Creature | HD | AC | XP |
| ---: | ---: | :---: | -------- | --- | ---: | ---: |
| 153 | 16 | `U` | Umber Hulk | 20d8 | 20 | 75 |
| 154 | 16 | `C` | Gelatinous Cube | 45d8 | 18 | 36 |
| 155 | 16 | `r` | Giant Black Rat | 3d4 | 16 | 3 |
| 156 | 16 | `F` | Giant Green Dragon Fly | 5d8 | 20 | 58 |
| 157 | 16 | `P` | Fire Giant | 20d8 | 40 | 62 |
| 158 | 16 | `b` | Green Dragon Bat | 2d7 | 22 | 44 |
| 159 | 16 | `q` | Quasit | 5d8 | 30 | 48 |
| 160 | 17 | `T` | Troll | 17d8 | 40 | 64 |
| 161 | 17 | `E` | Water Spirit | 8d8 | 28 | 58 |
| 162 | 17 | `S` | Giant Brown Scorpion | 11d8 | 44 | 62 |
| 163 | 17 | `E` | Earth Spirit | 13d8 | 40 | 64 |
| 164 | 18 | `E` | Fire Spirit | 10d8 | 30 | 66 |
| 165 | 18 | `o` | Uruk-Hai Orc | 14d8 | 42 | 68 |
| 166 | 18 | `P` | Stone Giant | 22d8 | 40 | 80 |
| 167 | 19 | `g` | Stone Golem | 28d8 | 75 | 100 |
| 168 | 19 | `O` | Grey Ooze | 6d8 | 10 | 40 |
| 169 | 19 | `O` | Disenchanter Ooze | 6d8 | 15 | 50 |
| 170 | 19 | `r` | Giant Spotted Rat | 4d3 | 20 | 3 |
| 171 | 19 | `M` | Mummified Kobold | 13d8 | 24 | 46 |
| 172 | 19 | `K` | Killer Black Beetle | 18d8 | 46 | 75 |
| 173 | 19 | `m` | Red Mold | 17d8 | 16 | 64 |
| 174 | 20 | `Q` | Quylthulg | 4d8 | 1 | 200 |
| 175 | 20 | `b` | Giant Red Bat | 5d8 | 24 | 40 |
| 176 | 20 | `F` | Giant Black Dragon Fly | 4d8 | 22 | 58 |
| 177 | 20 | `P` | Cloud Giant | 24d8 | 44 | 125 |
| 178 | 21 | `b` | Black Dragon Bat | 2d8 | 24 | 50 |
| 179 | 21 | `b` | Blue Dragon Bat | 3d6 | 26 | 54 |
| 180 | 21 | `M` | Mummified Orc | 14d8 | 28 | 56 |
| 181 | 21 | `K` | Killer Boring Beetle | 18d8 | 48 | 70 |
| 182 | 22 | `K` | Killer Stag Beetle | 20d8 | 50 | 80 |
| 183 | 22 | `m` | Black Mold | 15d8 | 18 | 68 |
| 184 | 22 | `g` | Iron Golem | 80d8 | 99 | 160 |
| 185 | 22 | `S` | Giant Yellow Scorpion | 12d8 | 38 | 60 |
| 186 | 22 | `O` | Green Ooze | 4d8 | 5 | 6 |
| 187 | 23 | `O` | Black Ooze | 6d8 | 6 | 7 |
| 188 | 23 | `p` | Warrior | 15d8 | 40 | 60 |
| 189 | 23 | `b` | Red Dragon Bat | 3d8 | 28 | 60 |
| 190 | 23 | `K` | Killer Blue Beetle | 20d8 | 50 | 85 |
| 191 | 23 | `a` | Giant Silver Ant | 6d8 | 38 | 45 |
| 192 | 23 | `m` | Crimson Mold | 16d8 | 18 | 65 |
| 193 | 24 | `W` | Forest Wight | 12d8 | 30 | 140 |
| 194 | 24 | `p` | Berzerker | 15d8 | 20 | 65 |
| 195 | 24 | `M` | Mummified Human | 17d8 | 34 | 70 |
| 196 | 24 | `G` | Banshee | 6d8 | 24 | 60 |
| 197 | 25 | `T` | Giant Troll | 19d8 | 40 | 85 |
| 198 | 25 | `t` | Giant Brown Tick | 18d8 | 50 | 70 |
| 199 | 25 | `K` | Killer Red Beetle | 20d8 | 50 | 85 |
| 200 | 25 | `m` | Wooden Mold | 25d8 | 50 | 100 |
| 201 | 25 | `F` | Giant Blue Dragon Fly | 6d8 | 24 | 75 |

## Band 4: Deep Dungeon (DL 26–40)

75 native species spawning across dungeon levels 26–40. (75 species.)

| # | DL | Glyph | Creature | HD | AC | XP |
| ---: | ---: | :---: | -------- | --- | ---: | ---: |
| 202 | 26 | `A` | Giant Grey Ant Lion | 19d8 | 40 | 90 |
| 203 | 26 | `b` | Disenchanter Bat | 4d8 | 24 | 75 |
| 204 | 26 | `t` | Giant Fire Tick | 16d8 | 54 | 90 |
| 205 | 26 | `W` | White Wraith | 15d8 | 40 | 165 |
| 206 | 26 | `S` | Giant Black Scorpion | 13d8 | 50 | 85 |
| 207 | 26 | `O` | Clear Ooze | 4d8 | 14 | 12 |
| 208 | 27 | `K` | Killer Fire Beetle | 13d8 | 45 | 95 |
| 209 | 27 | `V` | Vampire | 20d8 | 45 | 175 |
| 210 | 27 | `F` | Giant Red Dragon Fly | 7d8 | 24 | 75 |
| 211 | 27 | `m` | Shimmering Mold | 32d8 | 24 | 180 |
| 212 | 28 | `p` | Black Knight | 25d8 | 60 | 140 |
| 213 | 28 | `p` | Mage | 10d8 | 30 | 150 |
| 214 | 28 | `T` | Ice Troll | 22d8 | 46 | 160 |
| 215 | 29 | `w` | Giant Purple Worm | 65d8 | 65 | 400 |
| 216 | 29 | `d` | Young Blue Dragon | 33d8 | 50 | 300 |
| 217 | 29 | `d` | Young White Dragon | 32d8 | 50 | 275 |
| 218 | 29 | `d` | Young Green Dragon | 32d8 | 50 | 290 |
| 219 | 29 | `b` | Giant Fire Bat | 5d8 | 30 | 85 |
| 220 | 29 | `r` | Giant Glowing Rat | 3d3 | 24 | 4 |
| 221 | 30 | `s` | Skeleton Troll | 14d8 | 55 | 225 |
| 222 | 30 | `b` | Giant Lightning Bat | 8d8 | 34 | 80 |
| 223 | 30 | `a` | Giant Static Ant | 8d8 | 40 | 80 |
| 224 | 30 | `W` | Grave Wight | 12d8 | 35 | 325 |
| 225 | 30 | `K` | Killer Slicer Beetle | 22d8 | 55 | 200 |
| 226 | 30 | `A` | Giant White Ant Lion | 20d8 | 45 | 175 |
| 227 | 31 | `G` | Ghost | 13d8 | 30 | 350 |
| 228 | 31 | `A` | Giant Black Ant Lion | 23d8 | 45 | 170 |
| 229 | 31 | `K` | Death Watch Beetle | 25d8 | 60 | 190 |
| 230 | 31 | `o` | Ogre Mage | 14d8 | 42 | 250 |
| 231 | 31 | `O` | Crystal Ooze | 12d8 | 30 | 8 |
| 232 | 32 | `T` | Two-Headed Troll | 14d8 | 48 | 275 |
| 233 | 32 | `E` | Invisible Stalker | 19d8 | 46 | 200 |
| 234 | 32 | `a` | Giant Hunter Ant | 12d8 | 40 | 150 |
| 235 | 32 | `p` | Ninja | 15d8 | 65 | 300 |
| 236 | 33 | `W` | Barrow Wight | 13d8 | 40 | 375 |
| 237 | 33 | `s` | Skeleton 2-Headed Troll | 20d8 | 48 | 325 |
| 238 | 33 | `E` | Water Elemental | 25d8 | 36 | 325 |
| 239 | 33 | `E` | Fire Elemental | 25d8 | 40 | 350 |
| 240 | 34 | `L` | Lich | 25d8 | 50 | 750 |
| 241 | 34 | `V` | Master Vampire | 23d8 | 55 | 700 |
| 242 | 34 | `T` | Spirit Troll | 15d8 | 56 | 425 |
| 243 | 34 | `S` | Giant Red Scorpion | 18d8 | 50 | 275 |
| 244 | 34 | `E` | Earth Elemental | 30d8 | 60 | 375 |
| 245 | 35 | `d` | Young Black Dragon | 32d8 | 55 | 600 |
| 246 | 35 | `d` | Young Red Dragon | 36d8 | 60 | 650 |
| 247 | 35 | `p` | Necromancer | 17d8 | 40 | 600 |
| 248 | 35 | `M` | Mummified Troll | 18d8 | 38 | 400 |
| 249 | 35 | `A` | Giant Red Ant Lion | 23d8 | 48 | 350 |
| 250 | 35 | `d` | Mature White Dragon | 48d8 | 65 | 1000 |
| 251 | 36 | `X` | Xorn | 20d8 | 80 | 650 |
| 252 | 36 | `A` | Giant Mottled Ant Lion | 24d8 | 50 | 350 |
| 253 | 36 | `W` | Grey Wraith | 23d8 | 50 | 700 |
| 254 | 36 | `d` | Young Multi-Hued Dragon | 40d8 | 55 | 1250 |
| 255 | 36 | `d` | Mature Blue Dragon | 48d8 | 75 | 1200 |
| 256 | 36 | `d` | Mature Green Dragon | 48d8 | 70 | 1100 |
| 257 | 37 | `K` | Iridescent Beetle | 32d8 | 60 | 850 |
| 258 | 37 | `V` | King Vampire | 38d8 | 65 | 1000 |
| 259 | 37 | `L` | King Lich | 52d8 | 65 | 1400 |
| 260 | 37 | `d` | Mature Red Dragon | 60d8 | 80 | 1400 |
| 261 | 37 | `d` | Mature Black Dragon | 58d8 | 55 | 1350 |
| 262 | 38 | `d` | Mature Multi-Hued Dragon | 80d8 | 65 | 1650 |
| 263 | 38 | `D` | Ancient White Dragon | 88d8 | 80 | 1500 |
| 264 | 38 | `W` | Emperor Wight | 48d8 | 40 | 1600 |
| 265 | 38 | `W` | Black Wraith | 50d8 | 55 | 1700 |
| 266 | 39 | `W` | Nether Wraith | 58d8 | 55 | 2100 |
| 267 | 39 | `p` | Sorcerer | 30d8 | 50 | 2150 |
| 268 | 39 | `D` | Ancient Blue Dragon | 87d8 | 90 | 2500 |
| 269 | 39 | `D` | Ancient Green Dragon | 90d8 | 85 | 2400 |
| 270 | 39 | `D` | Ancient Black Dragon | 90d8 | 90 | 2500 |
| 271 | 40 | `w` | Disenchanter Worms | 10d8 | 5 | 30 |
| 272 | 40 | `Q` | Rotting Quylthulg | 12d8 | 1 | 1000 |
| 273 | 40 | `D` | Ancient Red Dragon | 105d8 | 100 | 2750 |
| 274 | 40 | `q` | Death Quasit | 55d8 | 80 | 1000 |
| 275 | 40 | `L` | Emperor Lich | 190d8 | 75 | 10000 |
| 276 | 40 | `D` | Ancient Multi-Hued Dragon | 130d16 | 100 | 12000 |

## Endgame Uniques (DL 50–100)

The two winning endgame threats: Evil Iggy (DL 50) and the Balrog (DL 100). (2 species.)

| # | DL | Glyph | Creature | HD | AC | XP |
| ---: | ---: | :---: | -------- | --- | ---: | ---: |
| 277 | 50 | `p` | Evil Iggy | 150d16 | 80 | 18000 |
| 278 | 100 | `B` | Balrog | 125d24 | 125 | 55000 |

## Threat Notes

- **Passive-looking hazards**: Floating Eyes, molds, and jellies often apply paralysis, blindness, corrosion, or gear disenchantment rather than heavy raw melee damage; inspect unfamiliar glyphs with `/` or `x`.
- **Phasers & invisible foes**: Phase-wall (`CM2_PHASE`) monsters pass straight through closed doors and dungeon rock, and `CD_INVISIBLE` creatures require infravision or Detect Invisible.
- **Fast movers**: Fast monsters act extra times per turn and erase walking retreat margins; keep Phase Door or Teleport ready.
- **Spellcasters & summoners**: Break line of sight (`MAX_CAST_RANGE = 8`) around corridor corners. Deep liches and sorcerers pair `Cause Serious Wounds` (`8d8`), `Hold Person`, `Slow Person`, `Drain Mana`, and `Summon Undead`.
- **Dragon & Balrog breath**: Breath deals **16-bit uncapped** `current_HP / 4` (lightning) or `current_HP / 3` (all other elements), ignoring AC. Lowering a dragon's HP immediately shrinks its breath.
- **The Balrog (`#278`)**: The endgame target at `DL 100` (`3,000` HP, `125` AC, Fast, fire breath up to `1,000` damage, `4d12` + `2d6` + `CHG`). Prepare fire resistance, healing, and Free Action before engaging.

## Deep Threat Stats

Exact catalog values from `platforms/shared/catalog/monster_catalog_spec.json` for key late-game breathers and endgame uniques (`Sp%` shows `round(100 / freq)` and `1/N` cast chance). Every entry below except the Young Blue and Young Green Dragons carries `CD_MAX_HP` (`maxHP = N * S`):

| DL | Creature | Speed | HD | Max HP | AC | XP | Sp% |
| ---: | -------- | ----- | --- | ---: | ---: | ---: | --- |
| 29 | Young Blue Dragon | Normal | 33d8 | 264 | 50 | 300 | 9% (`1/11`) |
| 29 | Young Green Dragon | Normal | 32d8 | 256 | 50 | 290 | 9% (`1/11`) |
| 35 | Young Red Dragon | Normal | 36d8 | 288 | 60 | 650 | 10% (`1/10`) |
| 35 | Mature White Dragon | Normal | 48d8 | 384 | 65 | 1,000 | 10% (`1/10`) |
| 37 | Mature Red Dragon | Normal | 60d8 | 480 | 80 | 1,400 | 12% (`1/8`) |
| 38 | Ancient White Dragon | Fast | 88d8 | 704 | 80 | 1,500 | 12% (`1/8`) |
| 39 | Ancient Blue Dragon | Fast | 87d8 | 696 | 90 | 2,500 | 12% (`1/8`) |
| 40 | Ancient Red Dragon | Fast | 105d8 | 840 | 100 | 2,750 | 17% (`1/6`) |
| 40 | Emperor Lich | Fast | 190d8 | 1,520 | 75 | 10,000 | 50% (`1/2`) |
| 40 | Ancient Multi-Hued Dragon | Fast | 130d16 | 2,080 | 100 | 12,000 | 20% (`1/5`) |
| 50 | Evil Iggy | Fast | 150d16 | 2,400 | 80 | 18,000 | 33% (`1/3`) |
| 100 | Balrog | Fast | 125d24 | 3,000 | 125 | 55,000 | 33% (`1/3`) |
