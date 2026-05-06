# Moria8 Spell And Prayer Reference

<!-- markdownlint-disable MD013 -->

Moria8 ships the full current catalog of 31 mage spells and 31 priest prayers.
Class, book, level, mana, and fail data follow the Umoria-style tables in the
Commodore implementation. Effect behavior follows Moria8's reconciled
Moria/VMS/Umoria behavior, with tighter Commodore messaging where appropriate.

Classes:

- Mage: mage catalog, all 31 spells.
- Rogue: mage catalog, limited utility subset.
- Ranger: mage catalog, broad subset, no `Genocide`.
- Priest: priest catalog, all 31 prayers.
- Paladin: priest catalog, all 31 prayers with later/harder access.
- Warrior: no spells or prayers.

Use `F` to study from a carried book when eligible. Use `M` to cast mage magic
or `P` to pray. Mages use intelligence for spell power and mana. Priests and
Paladins use wisdom.

## Mage Books

| Book | Spells |
| ---- | ------ |
| Beginner's Spellbook | Magic Missile; Detect Monsters; Phase Door; Light Area; Cure Light Wounds; Find Hidden Traps/Doors; Stinking Cloud |
| Magick I | Confusion; Lightning Bolt; Trap/Door Destruction; Sleep I; Cure Poison; Teleport Self; Remove Curse; Frost Bolt; Turn Stone to Mud |
| Magick II | Create Food; Recharge Item I; Sleep II; Polymorph Other; Identify; Sleep III; Fire Bolt; Slow Monster |
| The Mages Guide | Frost Ball; Recharge Item II; Teleport Other; Haste Self; Fire Ball; Word of Destruction; Genocide |

## Mage Spell Table

`--` means that class cannot learn that spell.

| # | Spell | Book | Mage L/M/F | Rogue L/M/F | Ranger L/M/F |
| ---: | ----- | ---- | ---------- | ----------- | ------------ |
| 1 | Magic Missile | Beginner's Spellbook | 1/1/22 | -- | 3/1/30 |
| 2 | Detect Monsters | Beginner's Spellbook | 1/1/23 | 5/1/50 | 3/2/35 |
| 3 | Phase Door | Beginner's Spellbook | 1/2/24 | 7/2/55 | 3/2/35 |
| 4 | Light Area | Beginner's Spellbook | 1/2/26 | 9/3/60 | 5/3/35 |
| 5 | Cure Light Wounds | Beginner's Spellbook | 3/3/25 | 11/4/65 | 5/3/40 |
| 6 | Find Hidden Traps/Doors | Beginner's Spellbook | 3/3/25 | 13/5/70 | 5/4/45 |
| 7 | Stinking Cloud | Beginner's Spellbook | 3/3/27 | -- | 7/5/40 |
| 8 | Confusion | Magick I | 3/4/30 | 15/6/75 | 7/6/40 |
| 9 | Lightning Bolt | Magick I | 5/4/30 | -- | 9/7/40 |
| 10 | Trap/Door Destruction | Magick I | 5/5/30 | 17/7/80 | 9/8/45 |
| 11 | Sleep I | Magick I | 5/5/30 | 19/8/85 | 11/8/40 |
| 12 | Cure Poison | Magick I | 5/5/35 | 21/9/90 | 11/9/45 |
| 13 | Teleport Self | Magick I | 7/6/35 | -- | 13/10/45 |
| 14 | Remove Curse | Magick I | 7/6/50 | 23/10/95 | 13/11/55 |
| 15 | Frost Bolt | Magick I | 7/6/40 | -- | 15/12/50 |
| 16 | Turn Stone to Mud | Magick I | 9/7/44 | -- | 15/13/50 |
| 17 | Create Food | Magick II | 9/7/45 | 25/12/95 | 17/17/55 |
| 18 | Recharge Item I | Magick II | 9/7/75 | 27/15/99 | 17/17/90 |
| 19 | Sleep II | Magick II | 9/7/45 | -- | 21/17/55 |
| 20 | Polymorph Other | Magick II | 11/7/45 | -- | 21/19/60 |
| 21 | Identify | Magick II | 11/7/99 | 29/18/99 | 23/25/95 |
| 22 | Sleep III | Magick II | 13/7/50 | -- | 23/20/60 |
| 23 | Fire Bolt | Magick II | 15/9/50 | -- | 25/20/60 |
| 24 | Slow Monster | Magick II | 17/9/50 | -- | 25/21/65 |
| 25 | Frost Ball | The Mages Guide | 19/12/55 | -- | 27/21/65 |
| 26 | Recharge Item II | The Mages Guide | 21/12/90 | -- | 29/23/95 |
| 27 | Teleport Other | The Mages Guide | 23/12/60 | -- | 31/25/70 |
| 28 | Haste Self | The Mages Guide | 25/12/65 | -- | 33/25/75 |
| 29 | Fire Ball | The Mages Guide | 29/18/65 | -- | 35/25/80 |
| 30 | Word of Destruction | The Mages Guide | 33/21/80 | -- | 37/30/95 |
| 31 | Genocide | The Mages Guide | 37/25/95 | -- | -- |

## Mage Spell Effects

| Spell | Effect |
| ----- | ------ |
| Magic Missile | Directional bolt attack. |
| Detect Monsters | Reveals detectable monsters on the current panel; reports when none are found. |
| Phase Door | Short-range teleport to escape local danger. |
| Light Area | Lights the room or nearby area. |
| Cure Light Wounds | Small heal; silent at full HP. |
| Find Hidden Traps/Doors | Reveals hidden traps and secret doors. |
| Stinking Cloud | Small targeted area attack. |
| Confusion | Directional creature-confusion effect. |
| Lightning Bolt | Directional lightning bolt. |
| Trap/Door Destruction | Removes nearby traps and opens or removes nearby doors. |
| Sleep I | Directional single-target sleep. |
| Cure Poison | Removes or reduces poison. |
| Teleport Self | Longer escape teleport. |
| Remove Curse | Removes ordinary curses from eligible equipment. |
| Frost Bolt | Directional cold bolt. |
| Turn Stone to Mud | Converts a targeted wall/stone tile to passable floor. |
| Create Food | Creates food underfoot if the tile can accept it. |
| Recharge Item I | Attempts to recharge a wand or staff; can fail destructively. |
| Sleep II | Sleeps adjacent/local monsters. |
| Polymorph Other | Directional target replacement. |
| Identify | Identifies an eligible carried or equipped item. |
| Sleep III | Attempts to sleep visible monsters. |
| Fire Bolt | Directional fire bolt. |
| Slow Monster | Directional slow effect. |
| Frost Ball | Targeted cold ball attack. |
| Recharge Item II | Stronger recharge attempt with the same general risks. |
| Teleport Other | Directional monster teleport. |
| Haste Self | Temporary speed increase. |
| Fire Ball | Targeted fire ball attack. |
| Word of Destruction | Mutates nearby terrain and destroys nearby monsters/items in the affected area. |
| Genocide | Prompts for a monster glyph/type and removes matching monsters. |

## Priest Books

| Book | Prayers |
| ---- | ------- |
| Holy Prayer Book | Detect Evil; Cure Light Wounds; Bless; Remove Fear; Call Light; Find Traps; Detect Doors/Stairs; Slow Poison |
| Words of Wisdom | Blind Creature; Portal; Cure Medium Wounds; Chant; Sanctuary; Create Food; Remove Curse; Resist Heat and Cold |
| Chants and Blessings | Neutralize Poison; Orb of Draining; Cure Serious Wounds; Sense Invisible; Protection from Evil; Earthquake; Sense Surroundings; Cure Critical Wounds; Turn Undead |
| Exorcism | Prayer; Dispel Undead; Heal; Dispel Evil; Glyph of Warding; Holy Word |

## Priest Prayer Table

| # | Prayer | Book | Priest L/M/F | Paladin L/M/F |
| ---: | ------ | ---- | ------------ | ------------- |
| 1 | Detect Evil | Holy Prayer Book | 1/1/10 | 1/1/30 |
| 2 | Cure Light Wounds | Holy Prayer Book | 1/2/15 | 2/2/35 |
| 3 | Bless | Holy Prayer Book | 1/2/20 | 3/3/35 |
| 4 | Remove Fear | Holy Prayer Book | 1/2/25 | 5/3/35 |
| 5 | Call Light | Holy Prayer Book | 3/2/25 | 5/4/35 |
| 6 | Find Traps | Holy Prayer Book | 3/3/27 | 7/5/40 |
| 7 | Detect Doors/Stairs | Holy Prayer Book | 3/3/27 | 7/5/40 |
| 8 | Slow Poison | Holy Prayer Book | 3/3/28 | 9/7/40 |
| 9 | Blind Creature | Words of Wisdom | 5/4/29 | 9/7/40 |
| 10 | Portal | Words of Wisdom | 5/4/30 | 9/8/40 |
| 11 | Cure Medium Wounds | Words of Wisdom | 5/4/32 | 11/9/40 |
| 12 | Chant | Words of Wisdom | 5/5/34 | 11/10/45 |
| 13 | Sanctuary | Words of Wisdom | 7/5/36 | 11/10/45 |
| 14 | Create Food | Words of Wisdom | 7/5/38 | 13/10/45 |
| 15 | Remove Curse | Words of Wisdom | 7/6/38 | 13/11/45 |
| 16 | Resist Heat and Cold | Words of Wisdom | 7/7/38 | 15/13/45 |
| 17 | Neutralize Poison | Chants and Blessings | 9/6/38 | 15/15/50 |
| 18 | Orb of Draining | Chants and Blessings | 9/7/38 | 17/15/50 |
| 19 | Cure Serious Wounds | Chants and Blessings | 9/7/40 | 17/15/50 |
| 20 | Sense Invisible | Chants and Blessings | 11/8/42 | 19/15/50 |
| 21 | Protection from Evil | Chants and Blessings | 11/8/42 | 19/15/50 |
| 22 | Earthquake | Chants and Blessings | 11/9/55 | 21/17/50 |
| 23 | Sense Surroundings | Chants and Blessings | 13/10/45 | 23/17/50 |
| 24 | Cure Critical Wounds | Chants and Blessings | 13/11/45 | 25/20/50 |
| 25 | Turn Undead | Chants and Blessings | 15/12/50 | 27/21/50 |
| 26 | Prayer | Exorcism | 15/14/50 | 29/22/50 |
| 27 | Dispel Undead | Exorcism | 17/14/55 | 31/24/60 |
| 28 | Heal | Exorcism | 21/16/60 | 33/28/60 |
| 29 | Dispel Evil | Exorcism | 25/20/70 | 35/32/70 |
| 30 | Glyph of Warding | Exorcism | 33/24/90 | 37/36/90 |
| 31 | Holy Word | Exorcism | 39/32/80 | 39/38/90 |

## Priest Prayer Effects

| Prayer | Effect |
| ------ | ------ |
| Detect Evil | Reveals evil monsters on the current panel; reports when none are found. |
| Cure Light Wounds | Small heal; silent at full HP. |
| Bless | Temporary combat blessing. |
| Remove Fear | Clears fear if present. |
| Call Light | Lights the room or nearby area. |
| Find Traps | Reveals hidden traps. |
| Detect Doors/Stairs | Reveals secret doors and stairs. |
| Slow Poison | Reduces poison severity. |
| Blind Creature | Current implementation uses the shared directional confuse-style effect. |
| Portal | Teleport escape prayer. |
| Cure Medium Wounds | Moderate heal. |
| Chant | Stronger temporary blessing than Bless. |
| Sanctuary | Attempts to sleep adjacent monsters. |
| Create Food | Creates food underfoot if the tile can accept it. |
| Remove Curse | Removes ordinary curses from carried and equipped items. |
| Resist Heat and Cold | Temporary heat/fire and cold resistance timers; current hostile fire-breath path is reduced by the heat/fire half. |
| Neutralize Poison | Clears poison. |
| Orb of Draining | Targeted divine attack. |
| Cure Serious Wounds | Strong heal. |
| Sense Invisible | Temporary ability to sense invisible creatures. |
| Protection from Evil | Temporary protection effect against evil. |
| Earthquake | Mutates nearby terrain and can remove items or monsters in the affected area. |
| Sense Surroundings | Maps nearby surroundings. |
| Cure Critical Wounds | Very strong heal. |
| Turn Undead | Affects undead monsters. |
| Prayer | Strong temporary blessing. |
| Dispel Undead | Damages visible eligible undead. |
| Heal | Major heal. |
| Dispel Evil | Damages visible eligible evil monsters. |
| Glyph of Warding | Creates a warding glyph underfoot when the tile is clear. |
| Holy Word | Full major prayer: heals, cleanses fear/poison, restores stats, grants protection/invulnerability-style defense, and dispels evil. |

## Commodore Notes

Moria8 intentionally does not print a generic success banner for every spell or
prayer. Visible effects such as bolts, teleporting, terrain changes, and map
reveals usually speak for themselves. Silent no-op cases are reduced where that
would be misleading, but message behavior is not terminal-perfect Umoria.

Timed expiry text is also leaner than historical desktop Umoria. In particular,
some timed buffs have explicit onset feedback but no repeated rich status text.
