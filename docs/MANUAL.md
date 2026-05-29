# Moria8 Manual

Moria8 is a Commodore 64, Commodore 128, and Commodore Plus/4 adaptation of the
classic Moria roguelike. You create one adventurer, prepare in town, descend
through the dungeon, grow stronger, and try to defeat the Balrog.

This manual covers the current Commodore releases. Moria8 follows Moria and
Umoria closely in spirit, but it is not a byte-for-byte reproduction. The C64
and Plus/4 ports use compact 40-column interfaces and smaller active maps; the
C128 port uses an 80-column VDC display and a wider memory model.

## Starting The Game

Use the disk image for your machine:

- C64: `moria8-c64.d64`
- Plus/4: `moria8-plus4.d64`
- C128: `moria8-c128.d71`

The C64 version benefits from REU support when available because some creature
data can be fetched without as much disk loading. The C128 version uses its own
banked-memory path. The Plus/4 version uses a standard 1541-compatible disk
path.

Use `D)isk Setup` on the title screen before loading or saving if your save
disk is not already initialized. Program media and save media are deliberately
separated; the game blocks using the program disk as the save disk. Save device
selection supports devices 8-11 where the target platform supports them.

On first start, create a character by choosing race, class, sex, and rolled
stats. The game then generates a background, starting gold, hit points, mana
where applicable, and starting equipment.

## Character Basics

Moria8 uses the classic six stats:

| Stat | Main Uses |
| ---- | --------- |
| STR | Melee damage, heavy weapons, digging, bashing, carrying weight. |
| INT | Mage spell learning, mage mana, devices, disarming. |
| WIS | Priest prayer learning, priest mana, saving throw. |
| DEX | Hitting, dodging, multiple blows, and disarming. |
| CON | Hit points and bodily resistance. |
| CHR | Store prices and starting money. |

Races are Human, Half-Elf, Elf, Halfling, Gnome, Dwarf, Half-Orc, and
Half-Troll. Classes are Warrior, Mage, Priest, Rogue, Ranger, and Paladin.
Not every race can choose every class. Humans and Half-Elves can choose any
class; the stricter race/class limits follow the classic Moria tables.

Experience raises your level, which improves hit points, mana, combat ability,
searching, disarming, saving throws, and spell/prayer access. Level 40 is the
maximum. Different races and classes advance at different rates; powerful
combinations usually require more experience.

Several non-human races have infravision. Infravision can show nearby warm
monsters while you are in darkness. It does not reveal terrain, items, traps,
doors, or cold creatures, and blindness blocks it. Dwarves have the longest
natural infravision; potions of infravision temporarily add to the effective
range.

## Main Commands

Moria8 uses its own Commodore command layout. The in-game help screen is the
authoritative quick reference: press `?`.

### Movement

| Key | Action |
| --- | ------ |
| `H` / cursor left | Move west. |
| `L` / cursor right | Move east. |
| `K` / cursor up | Move north. |
| `J` / cursor down | Move south. |
| `Y` | Move northwest. |
| `U` | Move northeast. |
| `B` | Move southwest. |
| `N` | Move southeast. |
| `.` | Rest or stay for one turn. |
| `CTRL+R` | Rest until HP and mana are recovered. |
| `SHIFT` + direction | Run in that direction. |
| `<` | Go up stairs. |
| `>` | Go down stairs. |

The C128 help screen also shows numeric keypad movement: `7 8 9 / 4 5 6 /
1 2 3`, with `5` as stay.

### Action And Information Keys

| Key | Action |
| --- | ------ |
| `G` | Get item. |
| `D` | Drop item. |
| `I` | Inventory. |
| `E` | Equipment. |
| `W` | Wear or wield an item. |
| `T` | Take off equipment. |
| `Q` | Quaff potion. |
| `R` | Read scroll. |
| `A` | Aim wand. |
| `Z` | Use staff. |
| `F` | Study a book and gain a spell/prayer when eligible. |
| `M` | Cast a mage spell. |
| `P` | Pray a priest prayer. |
| `S` | Search for one turn. |
| `#` | Toggle search mode. |
| `O` | Open door. |
| `C` | Close door. |
| `X` | Look. |
| `/` | Monster recall by monster symbol. |
| `SHIFT+C` | Character sheet. |
| `SHIFT+F` | Fire a missile weapon. |
| `SHIFT+T` | Throw an item. |
| `SHIFT+E` | Eat food. |
| `SHIFT+R` | Refuel light. |
| `SHIFT+D` | Disarm a visible adjacent trap. |
| `CTRL+B` | Bash a door or monster. |
| `+` | Tunnel. |
| `SHIFT+S` | Save and quit after a successful save. |
| `SHIFT+Q` | Quit. |
| `CTRL+W` | Wizard/debug mode. Wizard games are not ordinary scored games. |

At prompts, `ESC`, `STOP`, or `Q` usually cancels. `SPACE` or `RETURN`
continues through messages. Inventory letters act directly in most item lists.

## The Town

The town is your supply base. It contains the six classic shops plus two
Moria8 extensions:

| Store | Typical Use |
| ----- | ----------- |
| General Store | Food and light. |
| Armory | Armor, shields, helms, gloves, boots. |
| Weaponsmith | Weapons. |
| Temple | Scrolls and potions useful to divine classes and survival. |
| Alchemy Shop | Potions. |
| Magic Shop | Wands, staffs, rings. |
| Black Market | Expensive mixed goods, often outside normal shop limits. |
| Home | Storage, not a normal buying/selling shop. |

Charisma affects ordinary store prices. The Black Market uses harsher special
pricing. Stores restock when you return to town.

Buy enough food and light before descending. Running out of either is an early
way to lose a promising character.

## The Dungeon

The dungeon is turn-based. Monsters act after your meaningful actions. Walking
into a monster attacks it. Standing still, searching, resting, eating, reading,
using items, changing equipment, and moving all spend game time.

Important dungeon habits:

- Keep a light source fueled.
- Carry food.
- Search suspicious dead ends and doorways.
- Retreat before you are nearly dead.
- Do not fight everything at once; corridors are safer than open rooms.
- Use stairs as exits, not just progression.
- Use `X` to look and `/` to check monster recall by symbol.
- Use run carefully; attacks, hazards, and interruptions should stop a run.

The C64 and Plus/4 dungeons use compact active maps and 40-column views. The
C128 view is wider and closer to terminal Moria, but the same core rules apply.

## Items And Equipment

Items may be unidentified, cursed, magical, or ordinary. Wear/wield decisions
matter: cursed equipment may not come off until the curse is removed. Heavy
weapons can be poor choices for weak characters even if their damage looks
large.

Inventory uses letter slots. Equipment uses fixed slots for weapon, body armor,
shield, head, hands, feet, light, and ring. Dropping an inventory item compacts
the pack, so item letters may change after removal.

Some items are learned by use. Potions, scrolls, wands, staffs, rings, armor,
and weapons become safer once identified. The `Identify` spell and similar
effects are valuable because unknown items are a major source of risk.

## Combat

Melee is automatic when you move into a monster. Ranged combat uses
`SHIFT+F` to fire a missile weapon or `SHIFT+T` to throw an item. `CTRL+B`
can bash; `+` tunnels through rock.

Armor class reduces your chance of being hit. Weapon bonuses, strength,
dexterity, class, and level affect your offense. Some monsters attack with
status effects, spells, breath, corrosion, fear, or other dangerous abilities.
If a new monster is hurting you faster than you can hurt it, leave.

Some weapons and stat combinations give more than one melee blow in a single
attack command. When a melee message ends with a count such as `(2/3)`, the
first number is successful hits and the second number is total blows attempted.

Monster recall display exists, but recall persistence is not complete in the
current Commodore builds. See [MONSTERS.md](MONSTERS.md) for the shipped
monster roster and threat notes.

## Magic

Mages, Rogues, and Rangers use mage spells. Priests and Paladins use prayers.
Warriors do not cast. Use `F` to study a book when eligible, then `M` to cast
or `P` to pray.

Spell and prayer access depends on class, level, book, mana, and the character's
prime stat. Mages care about intelligence; priests and paladins care about
wisdom. Casting beyond your strength can fail or exhaust you.

Moria8 includes the full 31 mage spells and 31 priest prayers from the current
catalog, though some message timing and feedback are intentionally tighter than
terminal Umoria. See [SPELLS.md](SPELLS.md) for levels, mana costs, fail rates,
book placement, and effect notes.

## Winning And Death

The long-term goal is to descend, survive, build enough power, and defeat the
Balrog. You will need strong equipment, reliable escape options, enough hit
points to survive sudden damage, and knowledge of which fights to avoid.

Unlike the original Moria games, death does not remove your savefile. This
slight deviation is to allow for more fun for those who choose to restore
after death, versus starting over.

For early-game advice, see [PLAYER_GUIDE.md](PLAYER_GUIDE.md).
