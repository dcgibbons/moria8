"""Brain v1 (§6.6): deterministic, explainable, only what the current goals need.

Layers, first match wins: prompt (and store) -> retreat -> look -> throw -> fight -> eat
-> light -> resupply -> rest -> shop -> descend -> hunt -> explore -> search -> stair-scum. Every
decision records (layer, reason, key). The brain reads only the fair-play
``View``, the observation's mode, stage, status line, HP and depth, and the
player knowledge in ``knowledge`` (creature names).
"""

from __future__ import annotations

import collections
import math
import re
from dataclasses import dataclass, field

from . import knowledge
from .magic import BLIND, BOOK_LEVELS, book_of, store_name, CHANT, CREATE_FOOD, ORB, PORTAL, SANCTUARY, FIRST_BOOK, PRAYER_BOOKS, CURE_LIGHT, CURE_MEDIUM, DETECT_DOORS, HEALS, REMOVE_FEAR, Magic
from .magic import DETECT_EVIL, DETECT_MONSTERS, RESIST_HEAT_COLD, MAGIC_MISSILE, PHASE_DOOR, FIND_TRAPS, CURE_POISON, TELEPORT_SELF, MAGE_ATTACKS, MAGE_BOOKS, books_for
from .magic import BLESS, PRIEST_FIND_TRAPS, SLOW_POISON, NEUTRALIZE_POISON, LIGHT_SPELLS
from .magic import AIMED, AT_CREATURES, ON_ITEM, CASTER_BOOK_LEVELS
from .game import ITEM_PROMPT, KEY_RUNSTOP, KEY_SPACE, Game, Mode, Observation
from .goals import CLASSES, RACE_KEYS, Goal
from .view import (DIRS, WALL, TYPE_DOOR_CLOSED, TYPE_DOOR_OPEN, TYPE_STAIRS_DN, TYPE_STAIRS_UP, TYPE_TRAP, UNKNOWN, WALKABLE_TYPES,
                   Creature, Pos, View, sealed_search_spots)

KEY_BASH = 0x02          # CTRL+B
KEY_REST = ord("5")      # rest one turn (waiting for a first strike)
KEY_AUTOREST = 0x12      # CTRL+R: rest until recovered or disturbed (TRN-007); heals at
                         # the doubled VMS resting rate (TRN-009)
KEY_EAT = 0xC5           # SHIFT+E
KEY_SEARCH = ord("S")
KEY_AIM = ord("A")       # CMD_AIM: "Aim which wand (a-v)?", then a direction
KEY_USE = ord("Z")       # CMD_USE: "Use which staff (a-v)?"
KEY_SEARCH_MODE = ord("#")   # CMD_SEARCH_MODE: toggles, no game turn
SEARCH_MODE_EVERY = 20       # steps between tries to turn search mode on
KEY_LOOK = ord("X")      # look along a direction; takes no game turn
KEY_WEAR = ord("W")
KEY_REFUEL = 0xD2        # SHIFT+R
KEY_THROW = 0xD4         # SHIFT+T
KEY_FIRE = 0xC6          # SHIFT+F: the wielded launcher at the first matching ammunition
KEY_DISARM = 0xC4        # SHIFT+D
KEY_PICKUP = ord("G")
KEY_DROP = ord("D")
# What the bot uses (the pack list names a stack without a plural): the rest
# is junk once the pack fills (worn-out gear, burnt-out torches).
# Something Recharge can work on, the cheapest first (Magic Shop, VMS prices):
# Mages and Rangers cast Recharge Item I 156,000 times with nothing to
# recharge, so M7 criterion 2 never saw it work (C128, 2026-11-04).
RECHARGEABLE = ("Staff of Detect Monsters", "Wand of Light", "Staff of Light")
# Wands and staffs (maintainer, 2026-11-04: "this is a big gap"): Mages out of
# mana, out of Phase Door and in melee were the late deaths of the day. Damage
# by the game's dice (FEATURE_MAP 8.3: bolts 4d8 and 6d8, balls 12, 48, 72).
ATTACK_WANDS = {"Wand of Fire Balls": 72.0, "Wand of Cold Balls": 48.0, "Wand of Frost": 27.0,
                "Wand of Lightning": 18.0, "Wand of Stinking Cloud": 12.0}
BALL_WANDS = frozenset({"Wand of Fire Balls", "Wand of Cold Balls", "Wand of Stinking Cloud"})   # radius 2
KEEP_ATTACK_WANDS = 3    # attack wands kept, the strongest kinds
BREEDER_MANA = 0.5       # share of a caster's mana an attack spell at a breeder leaves, for the escape
BALL_BREEDERS = 3        # breeders within a ball's radius of the target that are worth a ball's charge
TELEPORT_STAFF = "Staff of Teleportation"   # a long jump: outruns what Phase Door does not
TELEPORT_CHARGES_RICH = 8   # its charges kept once rich: a level-35 Priest with none read Phase Door
                            # four times at an Ancient Blue Dragon that kept finding it (2026-11-07)
TELEPORT_AWAY = "Wand of Teleport Away"     # sends the creature beside away
WAND_BUYS = ("Wand of Frost", "Wand of Lightning", "Wand of Stinking Cloud")   # the best the gold allows
WAND_GOLD = 600          # gold beyond the gear reserve for a Magic Shop trip for a wand or staff
# Unidentified items by their flavours (core/item_identification.s): "Blue
# Potion", "White Scroll" or "Scroll of Lumen", "Iron Wand", "Birch Staff".
# Tried when safe or identified (maintainer, 2026-11-04: identify spells and
# scrolls, and found potions and scrolls, were never used).
UNKNOWN_SCROLL_WORDS = frozenset({"Lumen", "Veritas", "Dura", "Libera", "Acuta", "Ferox", "Tutela"})
PICKED_ITEM = re.compile(r"You picked up (?:an? )?(.+?)\.(?: |$)")
THIS_IS = re.compile(r"This is (?:an? )?(.+?)\.(?: |$)")
CASTER_REST_MANA = 0.25  # below this share of mana a caster rests even with a creature lately close
DARK_HOPS = 10           # down-and-back hops a lightless character tries for a lit way up
# What else is worth picking up: what the bot drinks, reads or aims. Not every
# kept kind: spare torches (a slot each by fuel), lanterns and other classes'
# books filled packs until the stores refused even food (2026-11-05: refusals
# 1 per 100,000 steps before, hundreds after).
PICKUPS = ("Potion of Cure", "Potion of Neutralize", "Scroll of Phase Door", "Scroll of Teleportation",
           "Scroll of Word of Rec", "Scroll of Identify",
           "Wand of Fire Balls", "Wand of Cold Balls", "Wand of Frost", "Wand of Lightning",
           "Wand of Stinking Cloud", "Wand of Teleport Away", "Staff of Teleportation")
TRY_HP = 0.9             # unknown potions and scrolls are tried at this share of max HP or more
IDENTIFY = "Identify"    # the Mage and Ranger spell (Magick I; magic.ON_ITEM)
IDENTIFY_SCROLL = "Scroll of Identify"


def unknown_kind(name: str) -> str | None:
    """"potion", "scroll", "wand", "staff" or "ring" for an unidentified flavour name, else None."""
    name = re.sub(r"^(?:an? |\d+ )", "", name.strip())
    if name.endswith(" Potion"):
        return "potion"
    if name.endswith(" Scroll") or (name.startswith("Scroll of ") and name[len("Scroll of "):] in UNKNOWN_SCROLL_WORDS):
        return "scroll"
    for kind, suffix in (("wand", " Wand"), ("staff", " Staff"), ("ring", " Ring")):
        if name.endswith(suffix):
            return kind
    return None
CHARGES = re.compile(r"\((\d+) charges?\)")
# Any label after the name: "(5 charges)", or "(magik)" on one sensed but not
# identified, which the stricter form missed, so found duplicates were picked
# up again and again (2026-11-05: four Wands of Cold Balls).
PICKED_WAND = re.compile(r"You picked up (?:an? )?((?:Wand|Staff) of [A-Za-z' -]+?)(?: \((?:(\d+) charges?|[^)]*)\))?\.")
RECHARGE_SPELLS = ("Recharge Item I", "Recharge Item II")
RECHARGEABLE_GOLD = 300  # the dearest of them with the shop's markup
KEEP_PREFIXES = ("Ration", "Slime Mold", "Flask of Oil", "Wooden Torch", "Brass Lantern", "Potion of Cure", "Potion of Neutralize",
                 "Scroll of Word of Rec", "Scroll of Phase Door", "Scroll of Teleportation", "Holy Book", "Spellbook")
DROP_RETRY = 500         # steps before looking for junk again after finding none
KEY_RETURN = 0x0D
LOOK_RESULT = re.compile(r"You see an? (.+?)\.")
SLAIN = re.compile(r"You have slain the (.+?)\.")
HIT_NEWS = re.compile(r"hits|misses|slain|fails|dies|destroyed|resists|unaffected|unharmed|immune|shrugs")
CASTS_A_SPELL = re.compile(r"[Tt]he (.+?) (?:casts a spell|frightens you)")
AVOID_GLYPHS = {"e"}     # Floating Eye: paralysing gaze when meleed
RETREAT_HP = 0.60
RETREAT_RANGE = 12       # farthest staircase worth running for; beyond, fight (round 28)
TRAP_HP = 0.50           # below this share of HP a known trap is impassable (round 20)
BUMP_STEPS = 10          # steps a tile stays blocked after a move into it went nowhere
LOOP_BLOCK_DOUBLINGS = 10   # an oscillation's tile, blocked again, twice as long each time: up to 10,240 steps
UNSEEN_STEPS = 20        # steps an attack from something unseen keeps the bot from resting (M4)
OSCILLATION_STEPS = 6    # command stops alternating between two squares before one is blocked (M4)
LOOP_WINDOW = 40         # moves kept to catch a longer circuit (M6) ...
LOOP_VISITS = 4          # ... a square entered this often within them ...
LOOP_SQUARES = 12        # ... while they cover no more than this many squares is a loop
CASTER_MEMORY = 100      # steps a caster seen or heard on the level still counts (M5f)
CASTER_BURSTS = 2        # its biggest spells in a row that must not be able to kill (M5f round 8)
NEAR_STEPS = 5           # steps a creature seen within 2 squares keeps the bot from resting (M4)
STILL_LAYERS = ("fallback", "rest", "search", "hunt", "stair-scum")   # layers that may stand still
STRONG_HP_BASE, STRONG_HP_PER_LEVEL = 20, 4   # more average HP than base + this x character level: too strong
STRONG_AC_BASE, STRONG_AC_PER_LEVEL = 20, 3   # ... or more AC than base + this x character level
DETECT_EVERY = 2000      # steps between Detect Doors/Stairs prayers on one level (M5b)
BREEDERS_LEAVE = 3       # breeding creatures in view at which the level is left (M5b)
SWARM_RECALL = 4         # fast breeders in view at which Word of Recall is read at once
EAT_CLEAR = 5            # a creature this close puts off a meal while only Hungry (M5a)
COINS_ODDS = 0.5         # fight odds under which Creeping Coins are fought, not walked away from (M5a)
FIGHT_ODDS = 0.6         # ... or more than this share of the turns it needs to kill the character: at
                         # 1.0 a fight is a coin flip (M5a round 7; 1.0 until round 6)
# Melee skill: class base and per level (core/tables.s class_properties BTH,
# class_level_adj BTH) plus the race's (race_properties BTH).
CLASS_BTH = {"warrior": (70, 4), "mage": (34, 2), "priest": (48, 2), "rogue": (60, 3), "ranger": (56, 3),
             "paladin": (68, 3)}
RACE_BTH = {"human": 0, "half-elf": -1, "elf": -5, "halfling": -10, "gnome": -8, "dwarf": 15, "half-orc": 12,
            "half-troll": 20}
CLASS_BTHB = {"warrior": (55, 4), "mage": (20, 2), "priest": (35, 2), "rogue": (66, 4), "ranger": (72, 4),
              "paladin": (40, 3)}   # missile skill and its gain a level (core/tables.s class_properties)
RACE_BTHB = {"human": 0, "half-elf": 5, "elf": 15, "halfling": 20, "gnome": 12, "dwarf": 0, "half-orc": -5,
             "half-troll": -10}
REFERENCE_AC = 20        # creature armour weapons are compared at (DL1-5 creatures: AC 10-30)
TOUGH_LOSS = 0.5         # HP share lost to one kind of creature, still alive, that marks it tough
TOUGH_LEVELS = 3         # character levels until a tough kind is worth fighting again
CROWD_RANGE, CROWD_COUNT = 3, 2   # this many creatures this close to a staircase: take it (M4 round 88)
CLEAR_WAY_CALM = 6       # no other creature this close before going to kill a blocker (M4 round 78)
CLEAR_HOLD = 100         # steps a chosen blocker is waited for while something moves near it
CLEAR_SKIP = 1000        # ... then it is not chosen again for this long
STILL_STEPS = 20         # steps a creature stays on one square before it counts as not coming (asleep)
SLOW_MEMORY = 30         # steps a slow creature out of sight still counts as a hazard (M4 round 47)
SLOW_AVOID = 300         # ... and is avoided as if seen, unless the player stands beside its empty tile
FIRST_STRIKE_WAITS = 2   # turns to wait for an approaching creature to step into contact
ATTACK_WORDS = ("hits you", "misses you", "bites you", "touches you", "casts")
HUNT_HP = 0.80
COIN_GLYPH = "$"         # Creeping Coins: slow, poison touch, drop their gold when killed (MON-014)
COLLECT_STEPS = 12       # farthest gold or food in view worth walking to (MON-014 drops)
COLLECT_WALKS = 3 * COLLECT_STEPS   # walk decisions toward one item before giving it up
OPEN_TRIES, BASH_TRIES = 3, 8
DISARM_TRIES = 3         # disarm attempts on a known trap in the way, then walk over it
SEARCHES_PER_SPOT = 6
SEALED_SEARCHES = 25     # per spot when no exit is reachable: each search only
                         # sometimes finds an adjacent secret door (§14.3 round 7)
SEARCH_BUDGET = 120      # search actions per level before giving up on secret doors
STALL_STEPS = 300        # steps without new map knowledge or XP before stair-scumming
GENERAL_STORE = 0        # store index (entrance "1")
ARMOURY = 1              # store index (entrance "2")
WEAPONSMITH = 2          # store index (entrance "3")
GEAR_RESERVE = 200       # gold kept back from armour and weapons: the next trip's food and potions
GEAR_RESERVE_EARLY = 40  # ... below EARLY_LEVELS: a weapon beats a reserve at level 1 (M5b)
WEAPON_GOLD_EARLY = 110  # kept from armour while the starting Dagger is wielded: a War Hammer or Broad
                         # Sword after markup (60, a Mace, until M5b round 42: the Weaponsmith's random
                         # stock rarely had one that cheap, and 63 of 80 runs kept the Dagger)
EARLY_LEVELS = 5
BOOK_GOLD = {"Words of Wisdom": 110, "Chants and Blessings": 330, "Exorcism": 880,   # base price + 10% (M5b)
             "Magick I": 110, "Magick II": 440, "The Mages Guide to Power": 880}       # (M5f)
GEAR_TRIP_GOLD = 1000    # gold at which a town trip to spend it on armour and weapons is worth it (M5a)
GEAR_TRIP_WAIT = 5000    # steps after a town visit before gold alone is reason for another (M5a)
STARTING_FOOD = 5        # rations in the starting kit (VMS player_init, Umoria class_base_provisions;
STARTING_TORCHES = 4     # ... 1 each until the 2026-10-25 kit fix), and torches beyond the lit one
STARTING_WEAPON = ("Dagger", 0)               # core/game_loop.s starting equipment: (name, to-dam)
# Launchers (core/ranged_fire.s, MON-018): ammunition, damage multiplier and
# range; the ammunition's dice average (core/item_tables.s: 1d5, 1d4, 1d2).
LAUNCHERS = {"Heavy Crossbow": ("Bolt", 4, 35), "Composite Bow": ("Arrow", 4, 35), "Long Bow": ("Arrow", 3, 30),
             "Light Crossbow": ("Bolt", 3, 25), "Short Bow": ("Arrow", 2, 25), "Sling": ("Rock", 2, 20)}
AMMO_AVERAGE = {"Bolt": 3.0, "Arrow": 2.5, "Rock": 1.5}
AMMO_RESERVE = 20        # shots carried
AMMO_MAX_GOLD = 10       # most paid a shot: a Human Warrior paid 407 of 473 starting gold for a
                         # Sling and two Rock (+1,+1), then had none for potions (C128, 2026-11-04)
FIRE_RANGE = 8           # farthest in-line creature fired at
LAUNCHER_KEEP = 20       # gold kept back from the first launcher (later ones: the gear reserve)
STARTING_ARMOUR = {"ICAT_ARMOR": 4}           # Leather Armor [4,+0]; AC worn per armour slot
ARMOUR_SLOTS = ("ICAT_ARMOR", "ICAT_SHIELD", "ICAT_HELM", "ICAT_GLOVES", "ICAT_BOOTS")
STAT = re.compile(r"\b(ST|DX):\s*(\d+)(?:/(\d+|\*\*))?")
STATS = re.compile(r"\b(ST|IN|WI|DX|CO|CH):\s*(\d+)(?:/(\d+|\*\*))?")   # all six, for drain


def stat_value(base: str, extra: str) -> int:
    """A status-line stat as 18 + xx/10 for 18/xx. The game prints 18/100 as
    "18/00" (core/stat_display.s), which read as a bare 18 until 2026-11-07."""
    if extra in ("**", "00"):
        return 28
    return int(base) + (int(extra) // 10 if extra else 0)
# The equipment list ('E'): a worn armour slot, its name and [AC,+to-AC]
# (wrapped onto the next line on 40 columns).
EQUIP_LINE = re.compile(r"^\s*[a-z]\) (Body|Shield|Head|Hands|Feet):\s+(.*)$")
EQUIP_SLOTS = {"Body": "ICAT_ARMOR", "Shield": "ICAT_SHIELD", "Head": "ICAT_HELM",
               "Hands": "ICAT_GLOVES", "Feet": "ICAT_BOOTS"}
# A ring or amulet (Magic Shop, Black Market), worn or for sale: its name and
# the bonus shown, "[+5]" for Protection, "(+2)" for Strength and Wisdom;
# Speed, Slaying, the Magi and the resists show none.
JEWEL_NAME = re.compile(r"^((Ring|Amulet) of (.+?))(?: [\[(]([+-]\d+)[\])])?\s*$")
JEWEL_LINE = re.compile(r"^\s*[a-z]\) (Ring|Amulet):\s+(.*)$")
JEWEL_GOLD = 20000       # gold beyond the reserve before rings and amulets are shopped for
MELEE_KLASSES = ("warrior", "paladin", "rogue", "ranger")
# Ego weapons (core/ego_items.s): the name's suffix, and what it is worth on
# the dice: a slay by how much of the deep dungeon it applies to (evil is
# most of it, dragons among them), Flame's 2d4 a blow, Defender's +5 AC as
# a couple of points a blow. Named "Dagger (Defender)", they were looked up
# whole, scored 0 and never bought (2026-11-07).
EGO_WEAPON = re.compile(r"^(.+?) \((Holy Avenger|Defender|Slay Animal|Slay Evil|Slay Undead|Slay Dragon|Flame|Frost)\)$")
EGO_FACTOR = {"Holy Avenger": 1.6, "Slay Evil": 1.5, "Slay Dragon": 1.4, "Slay Undead": 1.15, "Slay Animal": 1.15}
EGO_FLAT = {"Flame": 5.0, "Frost": 5.0, "Defender": 2.0}
ARMOUR_HITS_TRIP = 5     # "is damaged!" messages (to-AC -1 each) that are a reason to go and replace armour
RESTORATION = "Potion of Restoration"   # restores every drained stat (Alchemist, Temple; 300 gp)
RESTORE_GOLD = 400
RESTORE_UNSEEN = 15      # a character first seen at this level or higher may be drained already: drink one
RECALL_WAIT_MAX = 3000   # longest wait before another town trip for Word of Recall
ENCHANT_ARMOR = "Scroll of Enchant Armor"   # Alchemist; +1 to-AC on a worn piece (VMS enchant() odds)
ENCHANT_GOLD = 20000     # gold beyond the reserve before scrolls of it are bought
ENCHANT_PER_VISIT = 8    # scrolls bought (and read in town) a visit
ENCHANT_PER_VISIT_RICH = 24   # ... once rich (MARKET_GEAR_GOLD): the stores' stock is the limit
ENCHANT_AC_PER_LEVEL = 2 # AC below this times the character level is worth enchanting
MARKET_GEAR_GOLD = 50000 # gold at which the Black Market is shopped for armour and weapons too
HURT_OUT_HP = 0.35       # below this share of HP with no healing potion left: Word of Recall
HURT_OUT_HP_NO_ESCAPE = 0.5   # ... with no escape at hand either: Recall takes 15-35 turns to come
LIT_EVERY = 4            # squares walked, lightless, between light spells
GEAR_ARMOUR = re.compile(r"^(.+?) \[(\d+)(?:,\s*([+-]\s*\d+))?")
GEAR_WEAPON = re.compile(r"^(.+?)(?: \(([+-]\d+),\s*([+-]\d+)\))?\s*$")
TEMPLE = 3               # store index (entrance "4"): potions and scrolls, named since stores identify stock
ALCHEMIST = 4            # store index (entrance "5"): VMS stocks Word of Recall 3 times in 21 there
MAGIC_SHOP = 5           # store index (entrance "6"): Mage books (M5f)
BLACK_MARKET = 6         # store index (entrance "7"): everything, at a premium
FIND_TRAPS_EVERY = 40    # steps between a Mage's Find Hidden Traps/Doors while exploring (M5f)
MARKET_GOLD = 600        # gold worth a Black Market trip for Word of Recall (M4 round 48: the
                         # Temple stocked it for 6 of 17 characters; drops pay for it, MON-014)
RECALL = "Scroll of Word of Rec"   # Word of Recall (the store line may cut the name short)
RECALL_RESERVE = 2       # scrolls to carry: town and back without the stairs (M4 round 44;
                         # 2 since round 62: scrolls stack, and sealed or stair-less levels starved)
STUCK_STEPS = 2000       # steps without new map or experience before reading Word of Recall
RECALL_FROM = 3          # shallowest level worth recalling home from
CLW_GOLD = 20            # gold worth a Temple trip for Cure Light Wounds (base 15 gp, VMS; 50 until M5b round 46)
RECALL_GOLD = 190        # ... for Word of Recall (base 150 gp, VMS; 200 until M5b round 46; M4 round 45: round 44's
                         # trips without the gold cost ~6,700 steps for 2 scrolls)
STATUS_GOLD = re.compile(r"AU:\s*(\d+)(K?)")   # 40 columns show 100,000 and up as thousands: "AU:739K"
STATUS_AC = re.compile(r"AC:\s*(-?\d+)")
CLW = "Potion of Cure Light"   # Cure Light Wounds (the store line may cut the name short)
CLW_SAVING = 2           # ... while saving for a prayer book (M5b)
CLW_RESERVE = 5          # potions to carry for a fight gone wrong (M4; 3 until round 56, when
                         # most deaths came after drinking all three and gold was plentiful)
# Stronger potions from the Temple for the deep goal (M7): a level-14 Warrior
# with 136 HP drank five Cure Light Wounds beside three creatures and died
# holding 17,000 gold. Best first; VMS prices.
CCW, CSW = "Potion of Cure Critical", "Potion of Cure Serious"
NEUTRALIZE = "Potion of Neutralize"   # Neutralize Poison (Temple, 75 gp VMS): a cure without mana
RESIST_HEAT = "Potion of Resist Heat"   # fire resistance for 10-19 turns (fire breath, monster_cast_breath)
RESIST_COLD = "Potion of Resist Cold"   # ... and cold, against frost breath
RESIST_RESERVE = 4       # carried from SCOUT_FROM deep, bought at the Black Market
# The potions of gain stat (VMS potions.inc; Moria8 since 2026-11-07) and the
# status label of the stat each raises: drunk when carried, and, rich, bought
# at the Black Market for a stat short of 18/100 (maintainer, 2026-11-07: "MAX
# OUT ALL OF ITS STATS").
GAIN_POTIONS = {"Potion of Gain Strength": "ST", "Potion of Gain Intelligence": "IN",
                "Potion of Gain Wisdom": "WI", "Potion of Gain Dexterity": "DX",
                "Potion of Gain Constitution": "CO", "Potion of Charisma": "CH"}
STAT_MAXED = 28          # 18/100 as track_stats reads it (18 + 100 // 10)
RESIST_WORTH = 0.25      # a breather whose breath, as resisted now, is this share of HP: resist first
NEUTRALIZE_RESERVE = 2   # carried from STRONG_LEVEL on the strong_potions goals
STRONG_GOLD = {CCW: 100, CSW: 40}
POTION_HEAL = {CLW: 8.0, CSW: 16.0, CCW: 24.0}   # 2d7, 4d7, 6d7 (VMS potions.inc cases 13-15)
GHOST_GLYPH = "G"        # ghosts pass through walls (VMS Moria)
PHASE_AGAIN = 30         # steps after a short phase in which contact again calls for a far teleport
SUMMON_MEMORY = 50       # steps a summoning heard still sends the deep goal home with no stairs known
BLIND_READ_WAIT = 20     # steps after "You can't see to read!" before a scroll is tried again
DRAIN_RESTS = 3          # steps in a row losing HP, nothing attacking, that mean unseen poison (deep goal)
DRAIN_RECALL_HP = 0.6    # ... and the HP share below which it recalls to town for a cure
DEEP_DLVL = 10           # from here the deep goal leaves a level holding a creature it would lose to
# Caution by danger (maintainer, 2026-11-03). Danger is the most melee and
# spell damage every creature in view could do to a square in the next turn.
DANGER_RANGE = 20        # creatures farther than this add no danger
DANGER_CAP = 2000
CAUTION_BACK = 0.4       # danger here over this share of HP: back away
CAUTION_SAFER = 0.8      # ... to a square with at most this share of the danger here
CAUTION_ESCAPE = 0.5     # below ESCAPE_LEVEL, danger over this share of HP: up the stairs underfoot or phase
ESCAPE_LEVEL = 10
CAUTION_HOLD = 0.7       # at this share of max HP or more, never back onto the square of two steps ago
LEAVE_DANGER = 2.0       # danger here over this many times HP: the level is left
PERILOUS = 0.3           # paths avoid squares whose melee danger exceeds this share of HP
REST_DANGER = 0.25       # rest only with danger here at most this share of HP
BREEDER_REST = 10        # nor within this many squares of a breeder seen lately
BREEDER_LEVEL = 15       # below this level, a level where BREEDERS_LEAVE breeders were seen is left
FORGET_STEPS = 500       # steps without progress after which remembered creatures and blocks are forgotten
MAGE_MELEE_LEVEL = 35    # a Mage walks to melee nothing before this level
# Depth readiness beyond character level: from (depth) on,
# (max HP, character level) by class row, and cure potions from DL3, Word of
# Recall from DL5. Rogues and Rangers take the Priest row (assumed: the
# report gave only the Mage, Priest and Warrior rows). Max HP gates DL2 only:
# 60 and 80 HP floors for DL3 and DL5 held Halfling and Gnome Mages (55-57 HP
# at clvl 17-18) on DL2 for whole games (run K), so the level column gates those.
# Mages from DL10 five levels over each depth, not three (2026-11-05): with
# the open M7 combinations all Mages bar one, their deaths sat at clvl 15-22
# about three over the depth, to Black Mambas, Guardian Nagas and giants.
PREPARED = {"mage": ((2, 30, 0), (3, 0, 11), (5, 0, 15), (10, 0, 15), (12, 0, 17), (14, 0, 19), (16, 0, 21),
                     (18, 0, 23), (20, 0, 25)),
            "priest": ((2, 30, 0), (3, 0, 9), (5, 0, 15)),
            "warrior": ((2, 30, 0), (3, 0, 4), (5, 0, 6))}
PREPARED_ROW = {"mage": "mage", "priest": "priest", "rogue": "priest", "ranger": "priest",
                "warrior": "warrior", "paladin": "warrior"}
PREPARED_CURES, PREPARED_CURES_DLVL = 2, 3
PREPARED_RECALL_DLVL = 5
MISSILE_FIRST = ("rogue", "ranger")   # classes whose launcher comes before a better melee weapon (M5d)
STRONG_RESERVE = 10      # strong potions to carry from STRONG_LEVEL (5 until an Elf Priest died on DL23 with 33,687 gold)
STRONG_LEVEL = 10
STRONG_DEFICIT = 25      # HP short of max that a Cure Light Wounds (2d7, VMS) would not answer
PHASE = "Scroll of Phase Door"   # a short teleport (VMS teleport(10)), at the Alchemist
PHASE_RESERVE = 3        # scrolls to carry for a fight with no step out (M5b)
PHASE_PER_DLVL = 3       # ... and one more per this many levels of the deepest (10 by DL30)
PHASE_RESERVE_RICH = 20  # ... and once rich (MARKET_GEAR_GOLD): 15 gp each, and a level-34 Priest
                         # with millions read its last two to a dragon and died (2026-11-07)
TELEPORT_SCROLL = "Scroll of Teleportation"   # VMS teleport(100), at the Alchemist (40 gp): the staff's long jump
TELEPORT_RESERVE = 5     # scrolls to carry from TELEPORT_FROM deep: a level-37 Priest out of Phase Door, its
TELEPORT_FROM = 20       # staff spent, met an Earth Elemental with 10,000K gold and none (C64 Balrog, 2026-11-08)
STRONG_PER_DLVL = 2      # strong potions: 5 + one per this many levels of the deepest, past STRONG_RESERVE
RECALL_RESERVE_RICH = 6  # Word of Recall to carry once rich: two a round trip, and a level-34 Priest
                         # with 4,000K gold recalled up every ~2,500 steps for more (2026-11-07)
SCOUT_FROM = 20          # dungeon level from which a level is scouted with detection on arrival
SCOUT_EVERY = 500        # ... and again every this many steps on it
BREATH_LETHAL = 0.9      # a caster in view whose biggest spell or breath is this share of HP or more: out of its sight
UNSEEN_BREATH_STEPS = 40 # steps a breath from out of sight is remembered as the next one's size
BREATHER_MEMORY = 300    # steps a breather seen on the level keeps the bot resting to its breath
LEAVE_WALK_STEPS = 10    # stairs farther than this on a deadly level: Word of Recall first
TELEPORT_JUMP = 10       # a move farther than this within a level: teleported, the unseen breath behind
DEEP_HEAL_HP = 0.75      # from SCOUT_FROM deep, below this share of HP: heal (potions, prayers) before walking on
BREATHES = re.compile(r"\bbreathes\b")
BREATH_ELEMENT = re.compile(r"\bbreathes (lightning|gas|acid|frost|fire)\b")   # monster_cast_breath
PARALYZES = re.compile(r"[Tt]he (.+?) paralyzes you")
GRAVE_DANGER = 0.5       # the next turn's expected damage, as a share of HP, that no prayer but an escape answers
PHASE_GOLD = 20          # gold worth an Alchemist trip for one (base 15 gp)
TELEPORT_GOLD = 60       # ... and for a Scroll of Teleportation (base 40 gp)
HEAL_AVERAGE = {CURE_MEDIUM: 10.0, CURE_LIGHT: 6.0}   # 4d4 and 3d3 (Umoria player_pray.cpp)
MAGE_HEAL_AVERAGE = {CURE_LIGHT: 10.0}                 # the Mage book's is 4d4 (Umoria player_magic.cpp)
PRAY_HEAL_HP = 0.5       # below this share of max HP a known heal is prayed (M5b; potions below QUAFF_HP)
SPELL_MARGIN = 0.75      # HP under this share of a caster's biggest spell in view: heal, do not hunt it (M5b)
QUAFF_HP = 0.3           # below this fraction of max HP, drink one
FOODS = ("Ration of Food", "Slime Mold")
SLIME = 1 / 3            # a Slime Mold feeds 500 turns, a Ration 1,500 (core/player_items.s)
FOOD_PER_DEPTH = 3       # one more ration of reserve per this many levels down (M4 round 42)
FOOD_RESERVE = 2         # below this many known foods, head for town (§14.3 round 3)
SHALLOW_DLVL = 2         # trips no deeper than this keep a smaller food reserve (M5b round 35)
SHALLOW_FOOD_RESERVE = 1
C64_MAP_AREA = 80 * 48   # the map the food reserve was tuned on; the 80-column ports' is 198x66 (M6)
FOOD_MAX = 20            # rations' worth to carry at most (10 until M4 round 80: items stack
                         # now, so food no longer fills the pack; maintainer: "carry more food")
RESTOCK_WAIT = 1500      # steps to keep playing after a town visit found no food
RESTOCK_BACKOFF_MAX = 16  # gear and restock waits double after each fruitless visit, up to this many times GEAR_TRIP_WAIT
RESTOCK_HOPS = 5         # stores restock on every return to town: hops to DL1 and
                         # back before waiting instead (§14.3 round 15)
AFRAID_TURNS = 8         # VMS fresh fear lasts randint(5) + 3 turns (§14.3 round 10)
FOOD_PER_VISIT = 16      # food purchases per town visit (5 until M4 round 42, 8 until round 80)
FOOD_EARLY_MAX = 8       # rations' worth to carry at most below EARLY_LEVELS (M5b round 50)
LANTERN, OIL, TORCH = "Brass Lantern", "Flask of Oil", "Wooden Torch"
LIGHT_TURNS = re.compile(r"\((\d+) turns\)")   # a light's fuel, shown identified or not
WORN_LIGHT = re.compile(r"You are wearing a (?:Wooden Torch|Brass Lantern) \((\d+) turns")
LIGHT_CHARGE_TURNS = 30   # each charge the game shows as a "turn" (core/turn.s LIGHT_TICKS_PER_CHARGE)
SPARE_TORCH_CHARGES = 34   # a spare torch worth counting: about a quarter of a new one's 134
OIL_RESERVE = 3          # flasks to carry: each refills the lantern (§14.3 round 13)
EARLY_LANTERN_OIL = 1    # ... of which only one is kept from throwing while early (EARLY_LEVELS)
FLASK_DAMAGE = 7         # 2d6 average, thrown
                         # or is thrown when fear blocks melee (round 22)
EXERCISE_EVERY = 100     # steps between spells tried for their effect on one level (M7 criterion 2)
HEAL_WINDOW = 8          # steps (a prayer's prompts included) within which a heal is judged by the next
HEALS_LOSING_STEPS = 10  # steps a losing heal leaves the escape due (``phase_due``)
ON_ITEM_RETRY = 20_000   # steps before an item spell that found nothing to work on is tried again
EXERCISE_HP = 0.7        # ... and the HP share an aimed trial needs
EXERCISE_MANA = 0.75     # ... and the mana share a quiet trial needs
ORB_RANGE = 6            # farthest in-line creature Orb of Draining is aimed at (M5b)
BLIND_TURNS = 10         # Blind Creature confuses for 10 turns (MX_CONFUSE): not again before
CHANT_ODDS = 0.4         # fight odds from which a coming fight is worth a Chant
CHANT_TURNS = 24         # Chant blesses 24-47 turns: counted from its shortest
BLESS_TURNS = 12         # Bless, 12-24 turns (VMS bless(randint(12)+12)): counted from its shortest (M5f)
THROW_RANGE = 5          # farthest in-line creature worth a thrown flask
OIL_THROW = 7            # flasks carried to throw, beyond the lantern's reserve (M5a)
OIL_EARLY = 10           # flasks to throw bought first while early, whatever else waits (M5b; 5 at 10 gp until round 48)
OIL_WORTH_HP = 8         # lore HP at which an approaching creature is worth a flask (M5a)
OIL_GOLD = 3             # a flask's base price (core/item_tables.s; VMS, 10 until M5b round 46)
TORCH_RESERVE = 3        # spare torches to carry: the light, or the lantern's backup (M4; 2 until M5b round 46)
EXPLORE_PINGPONG = 8     # explore steps spent between two squares that mark their frontier dead (M5b)
TORCH_TURNS = 4000       # a torch burns ~4,000 turns, a lantern or flask ~7,500: the
LAMP_TURNS = 7500        # screens show no torch charges, so a player keeps rough time
LIGHT_RESERVE = 2000     # turns of light left, with no refill, that send the player to town
CLIMB_LIGHT = 500        # more per level below town with no Word of Recall: the stairs are the way home
REFUEL_AT = 300          # turns of light left at which a flask goes into the lantern
# Stat rolls (maintainer, 2026-10-25: "I like the general policy - but make
# sure that would work"): reroll, as a player does, until the class's main
# stat and CON are good for the race and class. Base stats are d3+d4+d5+5
# (8-17) with a 73-84 total (core/player_create.s), so a fixed bar fails some
# characters (a Half-Troll Mage's INT never reaches 17, an Elf Mage's CON never
# 14). The bars: the main stat at least 17, or 2 below the best this race and
# class can have if that is lower; CON at least the middle of its range (base
# 13). About 5 rolls for a Human Priest, 3 for a Dwarf Priest, at most about
# 25 on average (Half-Troll Priest, Dwarf Rogue, Halfling Paladin).
MAIN_STAT = {"warrior": "STR", "mage": "INT", "priest": "WIS", "rogue": "DEX", "ranger": "INT", "paladin": "STR"}
ROLL_LIMIT = 50          # rolls before taking whatever is shown
STAT_ROW = re.compile(r"\b(STR|INT|WIS|DEX|CON|CHR): *\d+(?:/\d+)? +\( *(\d+)(?:/(\d+))?\)")   # "STR:15 (15)", "DEX: 9 ( 9)"


def roll_good(rows: list[str], race: str, klass: str) -> bool:
    """Whether the roll screen's race-adjusted stats, with the class's
    adjustments added, reach the bars above."""
    shown = {}
    for row in rows:
        for name, whole, extra in STAT_ROW.findall(row):
            shown[name] = int(whole) + (1 if extra else 0)   # 18/xx counts as above 18
    if len(shown) < len(knowledge.STAT_NAMES):
        return True   # not the roll screen as expected: take it
    race_adj, class_adj = knowledge.stat_adjustments()
    r, c = list(RACE_KEYS).index(race), CLASSES.index(klass)
    main, con = knowledge.STAT_NAMES.index(MAIN_STAT[klass]), knowledge.STAT_NAMES.index("CON")
    best_main = 17 + race_adj[r][main] + class_adj[c][main]
    return (shown[MAIN_STAT[klass]] + class_adj[c][main] >= min(17, best_main - 2)
            and shown["CON"] + class_adj[c][con] >= 13 + race_adj[r][con] + class_adj[c][con])


MAX_CLVL = 40   # MAX_PLAYER_LEVEL (docs/FEATURE_MAP.md)
STORE_ITEM = re.compile(r"^\s*([a-l])\) (?:\d+ )?(\S.*?)\s+(\d+) GP")   # a stack shows its count first
PACK_ITEM = re.compile(r"^\s*([a-v])\) (?:\d+ )?(\S.*)")   # a stack shows its count first
PACK_COUNT = re.compile(r"^\s*[a-v]\) (\d+) ")
CLIMB_HOPS = 6           # down-and-back hops without getting higher before Recall or exploring


def ready_level(dlvl: int, margin: int = 2, taper: tuple[int, int, int] | None = None) -> int:
    """Character level a player wants before entering ``dlvl``. Deaths kept
    clustering at the minimum: level n on DL n through round 17, so DL2 needs
    level 3 (round 18); then level 4 on DL3, so DL n >= 3 needs n + 2
    (round 24). DL1 is where a new character starts. A goal's ``margin``
    lowers that: depth goals do not need the XP (M4 round 60).

    ``taper`` (knee, deepest, level there): past the knee the wanted level
    rises in a straight line to ``level`` at ``deepest`` (M7, §23.3: clvl 25
    on DL30, where a margin would ask for level 30 and more). Past
    ``deepest`` the line carries on, up to the game's top level, 40
    (MAX_CLVL): the Balrog goal on DL57-100."""
    if dlvl <= 1:
        return 1
    level = min(dlvl + margin - (1 if dlvl == 2 and margin else 0), MAX_CLVL)
    if taper is None or dlvl <= taper[0]:
        return level
    knee, deepest, top = taper
    base = ready_level(knee, margin)
    return min(level, base + -(-(dlvl - knee) * (top - base) // (deepest - knee)))


@dataclass(frozen=True)
class Decision:
    key: int
    layer: str
    reason: str

    def as_dict(self) -> dict[str, object]:
        return {"key": f"${self.key:02X}", "layer": self.layer, "reason": self.reason}


def chebyshev(a: Pos, b: Pos) -> int:
    return max(abs(a[0] - b[0]), abs(a[1] - b[1]))


@dataclass
class LevelMemory:
    detect_after: int = 0   # step before which Detect Doors/Stairs is not prayed again (M5b)
    blind_until: int = 0    # step before which Blind Creature is not prayed again (M5b)
    door_attempts: dict[Pos, int] = field(default_factory=dict)
    disarm_attempts: dict[Pos, int] = field(default_factory=dict)
    blocked: set[Pos] = field(default_factory=set)
    searches: dict[Pos, int] = field(default_factory=dict)
    known: int = 0
    since_progress: int = 0
    scum: bool = False
    stall_reported: bool = False
    # (position, glyph) -> ("creature" | "item", name), from looking or being attacked
    identified: dict[tuple[Pos, str], tuple[str, str]] = field(default_factory=dict)
    looked: set[tuple[Pos, Pos]] = field(default_factory=set)   # (from, at): look once
    dead_frontier: set[Pos] = field(default_factory=set)   # stood on; revealed nothing
    explore_trail: list[Pos] = field(default_factory=list)  # where the last explore steps were decided
    stationary: dict[Pos, Creature] = field(default_factory=dict)   # never move: still there unseen
    retreat_to: Pos | None = None   # the staircase the current retreat runs for
    unseen_until: int = 0           # step before which an unseen attacker may still be there
    near_until: int = 0             # step before which a creature seen close may still follow
    groped: set[Pos] = field(default_factory=set)   # unknown squares already stepped into
    felt: set[Pos] = field(default_factory=set)   # unknown squares a move into went nowhere: walls in the dark
    glyphs: dict[Pos, str] = field(default_factory=dict)   # unidentified glyphs seen, on screen or not
    retreat_path: set[Pos] = field(default_factory=set)   # tiles the current retreat crossed
    retreat_failed: bool = False    # it doubled back: stand and fight until it ends
    bumped: dict[Pos, int] = field(default_factory=dict)   # tile -> step it is blocked until
    collected: set[Pos] = field(default_factory=set)   # tiles a pickup was tried on, or given up
    collect_walks: dict[Pos, int] = field(default_factory=dict)   # walk decisions toward each
    slow_seen: dict[Pos, int] = field(default_factory=dict)   # slow creature tile -> step last seen
    loop_blocks: dict[Pos, int] = field(default_factory=dict)   # tile -> times it ended an oscillation here
    breeders_seen: dict[Pos, int] = field(default_factory=dict)   # breeding creature tile -> step last seen
    still: dict[Pos, tuple[str, int]] = field(default_factory=dict)   # creature tile -> (glyph, step first seen there)
    kinds: dict[str, float] = field(default_factory=dict)   # glyph -> worst creature_danger seen beside (Genocide)
    up_target: Pos | None = None   # the up staircase a walk up is committed to
    route: list[Pos] = field(default_factory=list)   # the path a walk to a staircase keeps (committed_step)
    clear_target: Pos | None = None   # the blocker clear_way is walking to
    clear_waits: dict[Pos, int] = field(default_factory=dict)   # blocker tile -> steps waited for it
    lit_at: Pos | None = None         # where a light spell was last cast, lightless
    clear_skip: dict[Pos, int] = field(default_factory=dict)   # blocker tile -> step it may be chosen again
    casters: dict[tuple[str, int], int] = field(default_factory=dict)   # caster kind -> step last seen or heard
    scouted_at: int | None = None     # the step Detect Evil (or Detect Monsters) was last cast here
    deadly: Pos | None = None         # where a creature that could kill from full HP in one breath was seen
    breath: tuple[int, int] | None = None   # (step, HP lost) of the last breath taken
    breather: tuple[int, int] | None = None # (step last seen, biggest turn's burst) of the breathers seen
    # Each burst by the elements that divide it (none: a spell or an unknown
    # breath, unresisted) -> (step last seen, biggest turn's worth): one
    # unresisted breather no longer hides what resisting does to the others
    # (review, 2026-11-08).
    breathers: dict[frozenset[str], tuple[int, int]] = field(default_factory=dict)
    find_traps_after: int = 0       # step before which Find Hidden Traps/Doors is not cast again (M5f)
    exercise_after: int = 0         # step before which no spell is tried for its effect again (M7)
    summoned: int | None = None     # step a creature on this level was last heard summoning help (M7)
    phased: int | None = None       # step of the last short phase (Phase Door, scroll or spell)
    last_threat: Pos | None = None   # where the nearest creature that could reach the player was last seen
    seen: list[int] | None = None    # tile types as last seen: the game forgets unlit floor


class Brain:
    def __init__(self, goal: Goal, name: str = "BOT") -> None:
        self.goal = goal
        self.name = name
        self.rolls = 0                         # stat rolls seen at chargen
        self.level = LevelMemory()
        self.last_dlvl: int | None = None
        self.last_xp = 0
        self.pending: int | None = None        # answer for the next direction prompt
        self.messages = ""                     # the latest screen's message lines
        self.pending_item: int | None = None   # answer for the next item prompt
        self.waited = 0                        # first-strike waits for the current target
        self.unseen_attack = False             # attacked this turn with nothing in view
        self.attacked = False                  # attacked this turn (any message naming an attack)
        self.trail: list[Pos] = []             # recent command-stop positions (oscillation check)
        self.loop_trail: list[Pos] = []        # recent move positions (longer-circuit check)
        self.no_food = False                   # "You have no food." until food is bought or picked up
        self.shopped = False                   # done shopping on this town visit
        self.potions_done = False              # done at the Temple on this town visit
        self.magic_done = False                # done at the Magic Shop on this town visit
        self.poisoned = False                  # "You feel poisoned." until "You feel better." (M5f)
        self.market_done = False               # done at the Black Market on this town visit
        self.alchemist_done = False            # done at the Alchemy shop on this town visit
        self.armoury_done = False              # done at the Armoury on this town visit
        self.weapons_done = False              # done at the Weaponsmith on this town visit
        self.weapon = STARTING_WEAPON          # (kind, to-dam) wielded or bought to wield
        self.launcher: str | None = None       # the launcher carried (M5d)
        self.more_junk = False                 # the last pack listing showed more than the item dropped
        self.missiles = {"shots": 0, "kills": 0}   # launcher shots and the kills they made (M7, §23.7)
        self.fired = False                     # the last command was a shot: its news is on this screen
        self.wielding_launcher = False         # ... and wielded, the melee weapon in the pack
        self.ammo = 0                          # shots for it carried
        self.magic = Magic(goal.klass)         # spells known and the cast in progress (M5b; Mage books M5d)
        self.clvl = 1                          # character level at the last command screen
        self.adjacent: list[Creature] = []     # creatures beside the player this step (fight_odds)
        self.armour = dict(STARTING_ARMOUR)    # armour slot -> AC worn or bought to wear
        self.to_wear: list[str] = []           # bought, not yet worn or wielded
        self.gear: dict[str, tuple[str, object]] = {}   # store name -> what buying it changes
        self.recall = 0                        # Word of Recall scrolls carried
        self.recalling = False                 # read one; the yank comes in 15-29 turns
        self.max_dlvl = 0                      # deepest level reached (where recall returns)
        self.trip_dlvl = 0                     # deepest level since the last time in town
        self.map_scale = 1.0                   # the level's area against the C64's (food_reserve)
        self.at_store: int | None = None       # store the last walk into town led to
        self.clw = 0                           # Cure Light Wounds potions carried
        self.equip_checked = True              # the armour worn known (a new character's kit) or read since the last town
        self.listing_equipment = False         # the 'E' list is up: read it (prompt)
        self.armour_hits = 0                   # "is damaged!" messages since the armour was last read
        self.stat_max: dict[str, int] | None = None   # each stat's highest value seen; None: never read
        self.restoration = 0                   # Potions of Restoration carried
        self.gains: dict[str, int] = {}        # potions of gain stat carried, by name
        self.stat_now: dict[str, int] = {}     # each stat as the status lines last read it
        self.restore_due = False               # a stat is drained: buy and drink Restoration
        self.enchant_scrolls = 0               # Scrolls of Enchant Armor carried (read in town)
        self.ac_seen = 0                       # the status line's AC, last seen in the dungeon or town
        self.gold_seen = 0                     # ... and its gold
        self.jewels: dict[str, int] = {}       # "Ring"/"Amulet" -> the worn one's jewel_value (0 for none)
        self.jewel_names: dict[str, str] = {}  # ... and its name
        self.resist_heat = 0                   # Potions of Resist Heat carried
        self.resist_cold = 0                   # ... and of Resist Cold
        self.strong = {CCW: 0, CSW: 0}         # stronger healing potions carried (tactic strong_potions)
        self.phase = 0                         # Phase Door scrolls carried
        self.teleports = 0                     # Scrolls of Teleportation carried
        self.neutralize = 0                    # Neutralize Poison potions carried
        self.shop_buys = 0                     # purchases started on this town visit
        self.store_letter: str | None = None   # item letter for the next "Buy which item?"
        self.pending_look: tuple[Pos, str] | None = None   # glyph the last look aimed at
        self.aimed: tuple[Pos, str] | None = None   # glyph the last bolt, shot or flask was aimed at
        self.food = STARTING_FOOD              # foods carried, as a player counts them:
                                               # starting kit, +bought/picked up, -eaten
        self.buying: str | None = None         # store item named by the last B)uy
        self.bought: str | None = None         # purchase counted, undone if the store objects
        self.typing: list[int] = []            # haggle offer keys still to type
        self.lamp = False                      # wearing a Brass Lantern
        self.lamp_packed = False               # bought a lantern, not yet worn
        self.oil = 0                           # flasks of oil carried
        self.torches = STARTING_TORCHES        # spare torches carried
        self.light_left = TORCH_TURNS          # estimated turns of light (steps overcount)
        self.picked_light: int | None = None   # turns in the light just picked to wear
        self.last_stats = (10, 10)             # STR and DEX last read from the status lines
        self.dark = False                      # the light has gone out
        self.drain_hp: int | None = None       # HP at the last command step (note_drain)
        self.on_item_after: dict[str, int] = {}   # item spell -> step it is next exercised (ON_ITEM_RETRY)
        self.rechargeable = False              # a staff or wand bought for Recharge (RECHARGEABLE)
        self.wands: dict[str, int] = {}        # wand or staff -> charges known to be left
        self.unknown: collections.Counter[str] = collections.Counter()   # unidentified items carried, by flavour
        self.identifying: str | None = None    # the unknown item an Identify was cast on
        self.identify_scrolls = 0              # Scrolls of Identify carried
        self.picking_next: str | None = None   # the item a second prompt asks for (a Scroll of Identify's)
        self.dark_hops = 0                     # down-and-back hops tried in the dark (DARK_HOPS)
        self.last_aimed: str | None = None     # the wand or staff last aimed or used
        self.last_heal: tuple[int, int | None] = (0, None)   # HP and step of the last heal prayed
        self.heals_losing_until = 0            # step until which heals in contact count as losing
        self.picking: str | None = None        # item to pick at the next item prompt (wear, throw)
        self.listed = False                    # the wear prompt's item list is showing
        self.resupply_after = 0                # step before which town is not worth a trip
        self.recall_trip_after = 0             # ... for Word of Recall alone (the Alchemist may have none)
        self.recall_wait = RESTOCK_WAIT        # doubled each time a visit leaves without one
        self.climb_hops = 0                    # down-to-climb-back hops since it last got higher
        self.recall_look_after = 0             # stuck with no Recall counted: when to look in the pack again
        self.climb_from: int | None = None     # the level those hops began on
        self.gear_trip_after = 0               # ... for armour and weapons alone
        self.gear_trip_gold = GEAR_TRIP_GOLD   # gold that makes a trip for armour and weapons worth it
        self.restock_trip_after = 0            # ... for strong potions and Phase Door alone
        self.restock_wait = GEAR_TRIP_WAIT     # ... doubled by each visit that left without them
        self.gear_wait = GEAR_TRIP_WAIT        # gear_trip_after's wait, doubled by each visit that bought no gear
        self.gear_bought = False               # armour or a weapon bought on this town visit
        self.book_trip_after = 0               # ... for a prayer book alone
        self.books_owned = {books_for(goal.klass)[0]} if self.book_levels() is not None else set()
        self.book_next: str | None = None      # the book wanted at the Temple this visit
        self.chant_until = 0                   # step until which Chant is counted on
        self.search_mode_after = 0             # step before which search mode is not turned on again
        self.pack_full = False                 # the game said "Your pack is full."
        self.refused_at: str | None = None     # the store whose sale the full pack refused
        self.dropping = False                  # a drop prompt is open for junk
        self.drop_after = 0                    # step before which no junk is looked for again
        self.hops = 0                          # restock hops since supplies were last found
        self.afraid = 0                        # turns the player is too afraid to melee
        self.chased = False                    # attacked this turn by a creature faster than the player
        self.standing = False                  # hurt, stairs too far to run for: fight this turn
        self.last_move: tuple[Pos, Pos] | None = None   # (from, to) of the last movement decision
        self.last_attack: tuple[Pos, str] | None = None   # (tile, glyph) the last fight aimed at
        self.items_seen: dict[Pos, tuple[str, str]] = {}   # identified items on screen: (glyph, name)
        self.recent_attacker: str | None = None   # attacker named since the last command screen
        self.last_hp: int | None = None        # HP on the previous command screen
        self.rest_hp: int | None = None        # HP when the last decision was to rest (tactic drain)
        self.draining = 0                      # rests in a row that lost HP with nothing attacking
        self.blind_until = 0                   # step before which no scroll is read: the game refused one, blind
        self.fight_loss: dict[str, int] = {}   # creature name -> HP lost to it, not yet slain
        self.tough: dict[str, int] = {}        # creature name -> character level it beat the bot at
        self.paralyzers: set[str] = set()      # creatures, by name, whose touch has paralysed the bot
        self.last_pos: Pos | None = None       # the position on the last command screen (TELEPORT_JUMP)
        self.collect_to: Pos | None = None     # the item tile being walked to
        self.created_food: Pos | None = None   # where Create Food just left a ration
        self.positions: list[Pos] = []         # the last command-stop positions, newest last (caution)
        self.general_bought = False            # something bought at the General Store this visit
        self.general_gold = -1                 # gold at the last General Store visit that bought nothing
        self.noted_messages = ""               # message rows last counted (food, light)
        self.noted_on_prompt = False           # ... and whether on a prompt screen
        self.events: list[str] = []            # bot-quality events for the session (stalls)

    def state(self) -> dict[str, object]:
        """JSON-serializable state saved beside snapshots."""
        return {"last_dlvl": self.last_dlvl, "last_xp": self.last_xp,
                "scum": self.level.scum, "since_progress": self.level.since_progress}

    def decide(self, obs: Observation, view: View | None) -> Decision:
        messages = obs.rows[0] + obs.rows[1]
        self.messages = messages
        fear_news = self.track_fear(messages)   # on every screen: -more- too (round 14)
        if "Your spell fails." in messages:
            if self.magic.last == CHANT:
                self.chant_until = 0           # not chanted: pray it again
            elif self.magic.last == BLIND:
                self.level.blind_until = 0
        self.magic.note(messages)
        if self.magic.lost_book is not None:
            self.books_owned.discard(self.magic.lost_book)
            if self.magic.books and self.magic.lost_book in self.magic.books:
                self.magic.books = None   # the book prompt's order changed: read it again
            self.magic.lost_book = None
        self.magic.watch_cast(obs)
        if "No charges left." in messages and self.last_aimed is not None:
            self.wands[self.last_aimed] = 0
        if "You have nothing there." in messages and self.magic.last in ON_ITEM:
            # Recharge with no wand or staff: Mages cast Recharge Item I
            # 114,410 times for an effect it cannot show (C128, 2026-11-04).
            self.on_item_after[self.magic.last] = obs.step + ON_ITEM_RETRY
        if "You have nothing there." in messages and self.picking is not None and not ITEM_PROMPT.search(obs.rows[0]):
            self.nothing_carried()
        if "You feel poisoned." in messages or "poisons you." in messages:
            self.poisoned = True
        elif "You feel better." in messages:
            self.poisoned = False
        # An attack shown only behind -more- (while paralysed) still counts on
        # the next command screen, which may say no more than "You can move
        # again." (M4 round 51: seeds 1006, 1007 rested beside a White
        # Mushroom patch until it killed them).
        self.recent_attacker = knowledge.attacker(messages) or self.recent_attacker
        # On every screen: a paralysis shows only behind -more-, and a level-36
        # Priest learned nothing from three of them and meleed the Iridescent
        # Beetle until it died (C64 Balrog, 2026-11-08). By touch only: Hold
        # Person reads the same from across the room, and a Sorcerer's would
        # have sent the bot from every 'p' beside it (review, 2026-11-08).
        touch = knowledge.touch_paralyzers()
        self.paralyzers.update(m.group(1) for m in PARALYZES.finditer(messages) if m.group(1) in touch)
        if not (messages == self.noted_messages and self.noted_on_prompt):
            # Food and light news on every screen too: a third message pushes
            # earlier ones behind -more- (review). A screen repeating what a
            # prompt screen just showed is not news; repeats between command
            # screens are (two pickups in a row read the same).
            self.count_food(messages)
            self.track_light(messages)
            if "Your pack is full." in messages:
                self.pack_full = True
            if " is damaged!" in messages:
                # Acid takes one from a worn piece's to-AC (VMS minus_ac): the
                # armour counted at purchase stayed, and level-26+ characters
                # went about at AC 4 in [14,-14] plate with 284,000 gold
                # (2026-11-06).
                self.armour_hits += 1
                self.equip_checked = False
            self.track_missiles(messages)
        self.noted_messages, self.noted_on_prompt = messages, obs.mode != Mode.COMMAND
        if obs.mode != Mode.COMMAND:
            return self.prompt(obs)
        assert view is not None
        self.track_stats(obs)
        if obs.dlvl and "You create food." in messages:
            self.created_food = view.pos
        self.pending = self.pending_item = self.picking = None   # their prompts are past
        self.magic.watch_cast(obs, (len(view.tiles_of(TYPE_TRAP)),
                                    len(view.tiles_of(TYPE_DOOR_CLOSED) | view.tiles_of(TYPE_DOOR_OPEN)),
                                    len(view.stairs_up() | view.stairs_down())))
        if self.fired and re.search(r"dies|destroyed|slain", messages):
            self.missiles["kills"] += 1
        self.fired = False
        if self.aimed is not None:
            # A bolt that reached nothing says nothing, a flask "flies away":
            # no creature stood there, whatever the glyph was taken for. A
            # '$' identified as Creeping Coins stayed one after they moved or
            # died, and Mages cast 14,805 Magic Missiles at floor gold (M5f
            # round 9), out of mana and oil for the next Kobold.
            target, self.aimed = self.aimed, None
            if "flies away" in messages or not HIT_NEWS.search(messages):
                self.level.identified[target] = ("item", "nothing there")
        self.clvl = obs.clvl
        self.book_next = self.book_wanted(obs)
        self.standing = False
        self.track(obs, view)
        self.remember_tiles(view)
        self.light_left -= 2 if "Search" in obs.rows[21] else 1   # rough time: search mode spends two turns a step
        if self.afraid and not fear_news:
            self.afraid -= 1
        attacker, self.recent_attacker = self.recent_attacker, None
        self.chased = attacker in knowledge.fast_creatures()
        if BREATHES.search(messages) and self.last_hp is not None and self.last_hp > obs.hp and obs.dlvl:
            element = BREATH_ELEMENT.search(messages)
            self.note_breath(obs, view, self.last_hp - obs.hp, element.group(1) if element else None)
        self.note_toughness(obs, attacker, messages)
        if self.last_attack is not None and self.last_attack[0] == view.pos:
            # The attack walked onto the tile: nothing was there (round 20).
            self.level.identified[self.last_attack] = ("item", self.last_attack[1])
        self.last_attack = None
        self.remember_glyphs(view)
        self.identify(view, messages, attacker)
        self.remember_stationary(view)
        self.note_breathers(obs, view)
        if self.last_pos is not None and chebyshev(self.last_pos, view.pos) > TELEPORT_JUMP:
            # Teleported (Portal, a staff): the breath taken unseen is behind.
            # A level-36 Priest cast Portal five times running on its memory and
            # had no mana left for the dragon that found it (C64, 2026-11-08).
            self.level.breath = None
        self.last_pos = view.pos
        # Slow creatures not worth a fight are kept at a distance like the
        # stationary ones: explore stepped back beside retreated-from coins
        # every other turn (M4 round 46, seed 1002). By kind, not glyph: a
        # White Worm mass shares 'w' with the faster Giant Purple Worm, and a
        # Half-Elf Ranger walked away from worms and straight back on the path
        # to the stairs until the colony bred around it (M5 regression, seed 1006).
        slow = {p for p, c in view.creatures.items()
                if (c.glyph, c.level) in knowledge.slow_kinds() and not self.coins_worth_it(c, obs)}
        self.level.slow_seen.update(dict.fromkeys(slow, obs.step))
        for pos in [p for p in self.level.slow_seen if p not in view.creatures and chebyshev(p, view.pos) <= 1]:
            del self.level.slow_seen[pos]   # beside it and nothing there: gone
        view.remembered = {p for p, seen in self.level.slow_seen.items()
                           if obs.step - seen < SLOW_AVOID and p not in view.creatures}
        # How long each creature has stood where it is: one seen on a square
        # not recorded for its kind moved, and so may every one of its kind.
        moved = {c.glyph for p, c in view.creatures.items() if self.level.still.get(p, ("",))[0] != c.glyph}
        for pos in [p for p, (glyph, _) in self.level.still.items() if glyph in moved]:
            del self.level.still[pos]
        for p, c in view.creatures.items():
            self.level.still.setdefault(p, (c.glyph, obs.step))
        breeders = knowledge.breeder_kinds()
        self.level.breeders_seen.update(dict.fromkeys(
            [p for p, c in view.creatures.items() if (c.glyph, c.level) in breeders], obs.step))
        # A nest out of sight is still there, avoided as a slow creature is:
        # steering the path only while in view, rats sent a level-19 Warrior
        # east and back west along one DL1 corridor, 79 times in 1,000 steps
        # (C128, 2026-11-06).
        view.remembered |= {p for p, seen in self.level.breeders_seen.items()
                            if obs.step - seen < SLOW_AVOID and p not in view.creatures and chebyshev(p, view.pos) > 1}
        for c in view.creatures.values():   # what Genocide would wipe out (genocide_key)
            self.level.kinds[c.glyph] = max(self.level.kinds.get(c.glyph, 0.0), self.creature_danger(c, 1, obs))
        if obs.clvl < BREEDER_LEVEL and len(self.level.breeders_seen) >= BREEDERS_LEAVE:
            # A weak character (below clvl 15) leaves a breeding level.
            self.level.scum = True
        view.perilous = self.perilous(view, obs)
        if obs.dlvl and self.danger(view.pos, view, obs) > LEAVE_DANGER * max(obs.hp, 1):
            self.level.scum = True   # danger over twice HP: leave the level
        if self.level.since_progress and self.level.since_progress % FORGET_STEPS == 0:
            # Each 500 steps with no progress: forget what was remembered,
            # memories that kept the bot circling are the likeliest culprits.
            # Once, not every step after: cleared each step, a square
            # ``break_oscillation`` blocked was open again at once, and
            # characters walked away from a slow creature and back to the
            # stairs past it 100 times in 1,000 steps (C128, 2026-11-04). The
            # loop counts stay, so a loop that comes back is blocked longer.
            self.level.slow_seen.clear()
            self.level.bumped.clear()
            view.remembered = set()
        if obs.mode == Mode.COMMAND and (not self.positions or self.positions[-1] != view.pos):
            self.positions = (self.positions + [view.pos])[-3:]
        burst = knowledge.spell_burst()
        self.level.casters.update(dict.fromkeys(
            [(c.glyph, c.level) for c in view.creatures.values() if burst.get((c.glyph, c.level))]
            + [kind for name in CASTS_A_SPELL.findall(messages)
               if (kind := knowledge.kinds_by_name().get(name)) is not None and burst.get(kind)], obs.step))
        view.hazards = set(self.level.stationary) | {
            p for p, seen in self.level.slow_seen.items() if obs.step - seen < SLOW_MEMORY}
        if any(self.dangerous(c, obs) for c in view.creatures.values()):
            self.level.scum = True
        if sum((c.glyph, c.level) in knowledge.breeder_kinds() for c in view.creatures.values()) >= BREEDERS_LEAVE:
            # A swarm only grows: leave the level (M5b round 1: a Paladin
            # fought multiplying White Worm masses on DL1 for 3,400 steps).
            self.level.scum = True
        self.attacked = attacker is not None or any(w in messages for w in ATTACK_WORDS)
        # Unseen: nothing in view, or a named attacker drawn unlike anything in
        # view (M4 round 89: seed 1028 auto-rested under a hidden Novice
        # Priest's wound spells because a Floating Eye was in view).
        drawn = knowledge.glyphs_of().get(attacker, frozenset()) if attacker is not None else None
        self.unseen_attack = self.attacked and (
            not view.creatures
            or (drawn is not None and not drawn & {c.glyph for c in view.creatures.values()}))
        if self.unseen_attack:
            self.level.unseen_until = obs.step + UNSEEN_STEPS
        near = [p for p in view.creatures if chebyshev(p, view.pos) <= 2] + [
            p for p, g in view.unknown.items() if g in knowledge.creature_glyphs() and chebyshev(p, view.pos) <= 2]
        if near:
            self.level.near_until = obs.step + NEAR_STEPS
        self.note_bump(obs, view)
        view.blocked = (self.level.blocked | (set(self.level.stationary) - set(view.creatures))
                        | {p for p, until in self.level.bumped.items() if until > obs.step})
        if obs.hp < TRAP_HP * obs.mhp:
            view.blocked |= view.tiles_of(TYPE_TRAP)   # a trap could kill (round 20)
        threats = self.threats(view)
        if threats:
            self.level.last_threat = min(threats, key=lambda p: chebyshev(p, view.pos))
        self.adjacent = [c for p, c in view.creatures.items() if chebyshev(p, view.pos) == 1]
        self.note_drain(obs)
        if "You can't see to read!" in messages:
            # Blind: the refusal takes no turn, so reading again repeats it
            # forever while the blindness (a turn timer) never runs down.
            # Five deep runs spent 1.9M of 2M steps re-reading Word of
            # Recall (M7 queue, 2026-11-01). Do something that takes turns.
            self.blind_until = obs.step + BLIND_READ_WAIT
        ghost = attacker is not None and GHOST_GLYPH in knowledge.glyphs_of().get(attacker, frozenset())
        tactics = self.goal.tactics
        if ("summoner" in tactics and "summons help!" in messages) or ("ghost" in tactics and ghost):
            # A ghost strikes from inside the walls, out of reach, and runs
            # down a runner: five characters on DL22-26 died to Banshees
            # holding their potions (same queue). Leave as from a summoner.
            # A summoner out of reach only adds to the fight: three deep
            # deaths on DL19-26 came beside a Magic User summoning again and
            # again (M7 queue, 2026-10-31). Leave the level.
            self.level.summoned, self.level.scum = obs.step, True
        decision = self.choose(obs, view)
        self.rest_hp = obs.hp if decision.layer == "rest" else None
        decision = self.shun_stationary(obs, view, decision)
        decision = self.break_oscillation(obs, view, decision)
        if decision.key in DIRS.values() and decision.layer not in ("look", "prompt"):
            step = next(d for d, k in DIRS.items() if k == decision.key)
            target = (view.pos[0] + step[0], view.pos[1] + step[1])
            # A fight move toward a creature is a move too; only an attack on
            # one in view stays in place by design. Sealed in, a C128 Dwarf
            # pressed the same step into a wall 650,000 times, walking to a
            # remembered Floating Eye (M7 queue, 2026-11-02).
            if decision.layer != "fight" or target not in view.creatures:
                self.last_move = (view.pos, target)
        return decision

    def note_drain(self, obs: Observation) -> None:
        """Deep goal: HP lost with nothing attacking, resting or not, is
        poison the messages did not show (a hit while away, behind -more-):
        two level-15 characters rested from 14 HP to death one point a turn
        (M7 queue, 2026-10-31), and four at clvl 9-10 walked to a shop or
        waited for Word of Recall from 5 HP to death, one with four Cure
        Light Wounds (C128, 2026-11-04). Three such steps in a row mark it."""
        if "drain" not in self.goal.tactics:
            return
        # Starving costs HP too: Weak or Faint is hunger, not poison.
        starving = any(word in obs.rows[23] for word in ("Weak", "Faint"))
        lost = self.drain_hp is not None and obs.hp < self.drain_hp and not self.attacked and not starving
        self.drain_hp = obs.hp
        if lost or self.rest_hp is not None and obs.hp < self.rest_hp and not self.attacked:
            self.draining += 1
            if self.draining >= DRAIN_RESTS:
                self.poisoned = True
        else:
            self.draining = 0

    def remember_tiles(self, view: View) -> None:
        """A player remembers the floor of a dark room after the torch has
        moved on; the game forgets it (VMS Moria remembers only lit, wall,
        door and object squares). Fill what the game forgot from what this
        level has shown before (M4 round 70: seed 1023 walked between two
        squares for 6,000 steps beside a remembered item whose floor kept
        turning unknown again)."""
        seen = self.level.seen
        if seen is not None and len(seen) == len(view.types):
            view.types = [m if t == UNKNOWN else t for t, m in zip(view.types, seen)]
        self.level.seen = view.types

    def note_bump(self, obs: Observation, view: View) -> None:
        """A move that left the player in place found something unseen on the
        tile (an invisible creature): keep off it for a while (round 17)."""
        if self.last_move is not None and self.last_move[0] == view.pos:
            self.level.bumped[self.last_move[1]] = obs.step + BUMP_STEPS
            if view.type_at(*self.last_move[1]) == UNKNOWN:
                self.level.felt.add(self.last_move[1])   # a wall in the dark: the game shows none
        self.last_move = None

    def choose(self, obs: Observation, view: View) -> Decision:
        # Short of food, a staircase hop to a fresh level comes before searching
        # walls; stair_scum still searches when no staircase is in reach (M4
        # rounds 37-38: seeds 1004, 1016 searched sealed DL1-2 pockets and
        # starved).
        if self.level.blocked and self.sealed(view):
            # A door given up on is the way out after all: bash it again
            # rather than search walls (M4 round 83: seed 1006 searched a room
            # 22,000 turns, its only door stuck after 11 tries).
            view.blocked = view.blocked - self.level.blocked
            self.level.blocked.clear()
            self.level.door_attempts.clear()
        last = (self.stair_scum, self.search) if self.food_low() else (self.search, self.stair_scum)
        for layer in (self.check_equipment, self.read_enchantments, self.search_mode, self.drop_junk, self.swat, self.shake_paralyzer, self.quaff, self.resist_fire, self.breath_guard, self.take_created_food, self.pray, self.invoke, self.aim, self.shoot, self.throw, self.crowded, self.shun, self.retreat, self.phase_door, self.swarm_recall, self.hurt_out, self.leave_deadly, self.caution, self.look,
                      self.cornered_cast, self.fight, self.leave_caster, self.eat,
                      self.light,
                      self.wear,
                      self.recall_trip, self.chosen_blocker, self.resupply,
                      self.rest, self.collect,
                      self.shop, self.scout, self.find_traps, self.identify_items, self.try_unknown, self.exercise, self.descend, self.hunt, self.explore, self.clear_way, *last):
            decision = layer(obs, view)
            if decision is not None:
                return decision
        decision = self.grope(view)   # feeling into the dark costs less than searching walls
        if decision is not None:
            return decision
        if self.level.searches and (obs.dlvl >= self.goal.target_dlvl or self.sealed(view)):
            # Searching again finds secret doors a pass missed (§14.3 round 4):
            # at goal depth, or when sealed in (round 7). Otherwise stair-scum
            # already leaves the level.
            self.level.searches.clear()
            per_spot = SEALED_SEARCHES if self.sealed(view) else SEARCHES_PER_SPOT
            decision = self.search(obs, view, forced=True, per_spot=per_spot)
            if decision is not None:
                return decision
        if obs.dlvl > 0 and obs.step < self.level.unseen_until:
            # Something unseen attacked lately: keep moving, not still.
            for (dx, dy), key in sorted(DIRS.items()):
                if view.passable(view.pos[0] + dx, view.pos[1] + dy, avoid_monsters=True):
                    return Decision(key, "fallback", "attacked unseen: keep moving")
        if obs.dlvl > 0:
            # A search takes the same one turn as resting and may find a
            # secret door; in the dark no wall is known, so no search spot is
            # (M4 round 70: seed 1029 rested 5,800 turns beside one).
            return Decision(KEY_SEARCH, "fallback", "nothing to do: search here")
        return Decision(ord("5"), "fallback", "nothing to do: rest a turn")

    @staticmethod
    def read_equipment(rows: list[str]) -> dict[str, int] | None:
        """Each armour slot's AC plus to-AC from the equipment list (0 for
        "(none)"), or None when the screen is not the list."""
        worn: dict[str, int] = {}
        for i, row in enumerate(rows):
            match = EQUIP_LINE.match(row)
            if match is None:
                continue
            text = match.group(2).strip()
            if "[" not in text and i + 1 < len(rows) and rows[i + 1].strip().startswith("["):
                text += " " + rows[i + 1].strip()
            ac = re.search(r"\[(-?\d+)(?:,\s*([+-]?\d+))?\]", text)
            worn[EQUIP_SLOTS[match.group(1)]] = 0 if ac is None else int(ac.group(1)) + int(ac.group(2) or 0)
        return worn or None

    def read_jewels(self, rows: list[str]) -> dict[str, int]:
        """The ring and amulet worn, by ``jewel_value`` (0 for "(none)")."""
        worn: dict[str, int] = {}
        for i, row in enumerate(rows):
            match = JEWEL_LINE.match(row)
            if match is None:
                continue
            text = match.group(2).strip()
            if i + 1 < len(rows) and re.match(r"^\s*[\[(][+-]\d+[\])]\s*$", rows[i + 1]):
                text += " " + rows[i + 1].strip()   # wrapped onto the next line on 40 columns
            worn[match.group(1)] = max(0, self.jewel_value(text))
            self.jewel_names[match.group(1)] = text
        return worn

    def jewel_value(self, name: str) -> int:
        """What a ring or amulet is worth to this character, as a player ranks
        them: Speed above all, the Magi's Free Action and See Invisible, then
        Protection by its bonus; Strength and Slaying for fighters, Wisdom for
        Priests and Paladins (their mana). Negative (cursed): -1."""
        match = JEWEL_NAME.match(name.strip())
        if match is None:
            return -1
        kind, bonus = match.group(3), int(match.group(4) or 0)
        if bonus < 0:
            return -1
        melee = self.goal.klass in MELEE_KLASSES
        return {"Speed": 1000, "the Magi": 300, "Protection": 10 * bonus,
                "Strength": 15 * bonus if melee else 0, "Slaying": 60 if melee else 0,
                "Wisdom": (20 if self.goal.klass in ("priest", "paladin") else 2) * bonus,
                "Resist Fire": 800, "Resist Cold": 800, "See Invisible": 20}.get(kind, 0)

    def gain_wanted(self, name: str) -> bool:
        """A potion of gain stat for a stat short of 18/100: picked up (and
        drunk, quaff). A level-36 Priest walked past a Potion of Gain
        Constitution six times on DL32 at 260 HP, its killers breathing 150 to
        234 (C64 Balrog, 2026-11-08)."""
        kind = next((k for k in GAIN_POTIONS if name.startswith(k)), None)
        return kind is not None and self.stat_now.get(GAIN_POTIONS[kind], 0) < STAT_MAXED

    def jewel_better(self, name: str) -> bool:
        """A ring or amulet better than the one worn in its slot: picked up
        and put on. A level-36 Priest walked past a Ring of Resist Fire eight
        times on DL32, every breath there fire, and died to them (C64 Balrog,
        2026-11-08)."""
        jewel = JEWEL_NAME.match(name.strip())
        return jewel is not None and self.jewel_value(name) > max(0, self.jewels.get(jewel.group(2), 0))

    def jewels_wanted(self, obs: Observation) -> bool:
        """Rich, and the ring or the amulet worn could be better."""
        return (self.gold(obs) >= JEWEL_GOLD + self.gear_reserve(obs)
                and (self.jewels.get("Ring", 0) < 1000 or self.jewels.get("Amulet", 0) < 300))

    def jewel_pick(self, obs: Observation) -> tuple[str, str] | None:
        """At the Magic Shop or the Black Market, rich: the ring or amulet
        that most improves what is worn, within the gold over the reserve.
        A level-34 Priest with 4,000K gold wore none (2026-11-07)."""
        gold = re.search(r"Gold: (\d+)", obs.rows[16])
        budget = (int(gold.group(1)) if gold else 0) - self.gear_reserve(obs)
        worn = dict(self.jewels)
        for name in self.to_wear:
            kind, change = self.gear.get(name, ("", None))
            if kind == "jewel":
                worn[change[0]] = max(worn.get(change[0], 0), change[1])
        best: tuple[int, int, str, str, str] | None = None
        for row in obs.rows[3:15]:
            match = STORE_ITEM.match(row)
            if match is None or int(match.group(3)) > budget:
                continue
            jewel = JEWEL_NAME.match(match.group(2).strip())
            if jewel is None:
                continue
            slot, value = jewel.group(2), self.jewel_value(match.group(2))
            gain = value - worn.get(slot, 0)
            if gain > 0 and (best is None or (gain, -int(match.group(3))) > (best[0], best[1])):
                best = (gain, -int(match.group(3)), match.group(1), match.group(2), slot)
        if best is None:
            return None
        self.gear[best[3]] = ("jewel", (best[4], best[0] + worn.get(best[4], 0)))
        return best[2], best[3]

    def check_equipment(self, obs: Observation, view: View) -> Decision | None:
        """Read the armour worn from the equipment list (no game turn): once a
        town visit, and after acid damaged a piece."""
        if self.equip_checked or self.close_threats(obs, view):
            return None
        self.equip_checked, self.listing_equipment = True, True
        return Decision(ord("E"), "gear", "look at the armour worn")

    def close_threats(self, obs: Observation, view: View) -> set[Pos]:
        """``threats``, but in town only those within two squares:
        townspeople are nearly always in view (as ``drop_junk``), and the
        armour was read after the Temple and the Armoury (2026-11-06)."""
        threats = self.threats(view)
        return {p for p in threats if chebyshev(p, view.pos) <= 2} if obs.dlvl == 0 else threats

    def enchant_wanted(self, gold: int) -> bool:
        """Rich and lightly armoured: Scrolls of Enchant Armor (VMS enchant():
        a piece at +0 or below always takes one, higher ones less and less).
        Bought armour tops out near AC 19; level-24+ deaths had AC 4-26 with
        100,000-700,000 gold (2026-11-06)."""
        cap = ENCHANT_PER_VISIT_RICH if gold >= MARKET_GEAR_GOLD else ENCHANT_PER_VISIT
        return (self.ac_seen < ENCHANT_AC_PER_LEVEL * self.clvl and self.enchant_scrolls < cap
                and gold >= ENCHANT_GOLD + GEAR_RESERVE)

    def read_enchantments(self, obs: Observation, view: View) -> Decision | None:
        """In town, read the Scrolls of Enchant Armor bought, then the armour
        list again (``check_equipment``)."""
        if obs.dlvl != 0 or not self.enchant_scrolls or self.close_threats(obs, view):
            return None
        self.picking, self.listed = ENCHANT_ARMOR, False
        return Decision(ord("R"), "gear", "read Enchant Armor")

    def track_stats(self, obs: Observation) -> None:
        """Each stat's highest value seen; one below it is drained, and a
        Potion of Restoration puts it back (the status line shows no drain:
        a level-29 Priest played at CON 3, 68 HP, 2026-11-06)."""
        ac = STATUS_AC.search(obs.rows[23]) or STATUS_AC.search(obs.rows[21])
        if ac:
            self.ac_seen = int(ac.group(1))
        if STATUS_GOLD.search(obs.rows[23]):
            self.gold_seen = self.gold(obs)
        found = {name: stat_value(base, extra)
                 for row in obs.rows[19:24] for name, base, extra in STATS.findall(row)}
        if len(found) < 6:
            return
        self.stat_now = found
        if self.stat_max is None:
            # Never read: a character met high may have lost some already.
            self.stat_max = dict(found)
            self.restore_due = obs.clvl >= RESTORE_UNSEEN
            return
        if any(found[k] < self.stat_max.get(k, 0) for k in found):
            self.restore_due = True
        for k, v in found.items():
            self.stat_max[k] = max(self.stat_max.get(k, 0), v)

    @staticmethod
    def sees(view: View, a: Pos, b: Pos) -> bool:
        """A straight line from ``a`` to ``b`` over the known map: walls and
        closed doors block it; an unknown square does not (it may be floor)."""
        (x, y), (x1, y1) = a, b
        dx, dy, sx, sy = abs(x1 - x), abs(y1 - y), 1 if x1 > x else -1, 1 if y1 > y else -1
        err = dx - dy
        while (x, y) != (x1, y1):
            e2 = 2 * err
            if e2 > -dy:
                err, x = err - dy, x + sx
            if e2 < dx:
                err, y = err + dx, y + sy
            if (x, y) != (x1, y1):
                t = view.type_at(x, y)
                if t != UNKNOWN and t not in WALKABLE_TYPES:
                    return False
        return True

    def resist_div(self, obs: Observation, element: str, lasting: bool = False,
                   assume: frozenset[str] = frozenset()) -> int:
        """What a breath of ``element`` is divided by now (monster_cast_breath,
        VMS fire_dam / cold_dam): a third with the Ring of Resist Fire (Cold),
        a third again with the Resist Heat (Cold) timer; lightning, gas and
        acid by nothing here. ``lasting``: the ring only, for what holds past
        the next turns (leave the level, rest first): the timer runs 10-19
        turns. A level-34 Priest resisted on sight of an Ancient White
        Dragon (234 as 78), so the level never read deadly; it teleported,
        explored on, and died to the next breath at 230/245 (C64 Balrog,
        2026-11-07). ``assume``: the elements whose timer is taken as running
        (a prayer or potion being weighed)."""
        rings = {"fire": ("Resist Fire", "zp_eff_resist"), "frost": ("Resist Cold", "eff_resist_cold_timer")}
        if element not in rings:
            return 1
        ring, timer = rings[element]
        held = ring in self.jewel_names.get("Ring", "")
        on = element in assume or (not lasting and obs.abi is not None and hasattr(obs.abi, timer)
                                   and obs.zp8(timer) > 0)
        return 3 ** (int(held) + int(on))

    def elements_div(self, obs: Observation, elements: frozenset[str], lasting: bool = False,
                     assume: frozenset[str] = frozenset()) -> int:
        """The divisor of the worst breath of ``elements`` (none known: 1)."""
        return min((self.resist_div(obs, e, lasting, assume) for e in elements), default=1)

    def burst_now(self, key: tuple[str, int], obs: Observation, lasting: bool = False,
                  assume: frozenset[str] = frozenset()) -> int:
        """The most one spell or breath of kind ``key`` does now, its breath
        divided by the resistance to its element (all five: the worst)."""
        info = knowledge.breath_info().get(key)
        if info is None:
            return knowledge.spell_burst().get(key, 0)
        breath, elements, other = info
        return max(other, breath // self.elements_div(obs, elements, lasting, assume))

    def resist_fire(self, obs: Observation, view: View) -> Decision | None:
        """A breather in view whose breath, resisted as now, is RESIST_WORTH
        of the HP: Resist Heat and Cold (Priest), else a Potion of Resist
        Heat or Cold, before anything else answers it. Six of a level-34
        Priest's first seven copies died to dragon breath, the prayer known
        (2026-11-07). Each breather by its own element: a resisted fire
        breath is worth the turn though a lightning breather is about too
        (review, 2026-11-08)."""
        if obs.dlvl == 0:
            return None
        both = frozenset({"fire", "frost"})

        def threats(assume: frozenset[str]) -> list[int]:
            # A turn's worth, each breath resisted: a fast breather acts twice
            # before the next turn, and two resisted breaths of an Ancient
            # White Dragon (78 each) kill at 100 HP, where one does not (the
            # 2026-11-08 review).
            out = [self.turn_burst(c, obs, assume=assume) for c in view.creatures.values()]
            if self.level.deadly is not None:
                # Out of sight too, on a level with a breath that could kill:
                # the timer runs 10-19 turns, and a level-36 Priest walking to
                # the stairs from an Ancient White Dragon met it again
                # unresisted (C64 Balrog, 2026-11-08).
                out += self.remembered_bursts(obs, assume=assume)
            return out

        now = threats(frozenset())
        worth = RESIST_WORTH * obs.hp

        def gains(assume: frozenset[str]) -> list[int]:
            # Only fire and frost are resisted (monster_cast_breath): nothing
            # to gain against lightning, gas, acid or all five.
            return [n for n, r in zip(now, threats(assume)) if r < n and n >= worth]

        helped = gains(both)
        if not helped:
            return None
        if max(threats(both)) >= BREATH_LETHAL * obs.hp:
            # Lethal even resisted: a turn to get away (breath_guard), not to
            # resist. A level-34 Priest at 38/245 prayed Resist Heat and Cold
            # in an Ancient White Dragon's sight; its breath, a third of 234,
            # still killed it (C64 Balrog, 2026-11-07).
            return None
        if self.magic.can(obs, RESIST_HEAT_COLD):
            return Decision(*self.magic.pray(RESIST_HEAT_COLD, f"a breath of {max(helped)} in view: pray {RESIST_HEAT_COLD}"))
        if obs.step < self.blind_until:
            return None
        potions = [(gains(frozenset({e})), name) for e, name, held in
                   (("fire", RESIST_HEAT, self.resist_heat), ("frost", RESIST_COLD, self.resist_cold)) if held]
        best = max(((max(g), name) for g, name in potions if g), default=None)
        if best is None:
            return None
        self.picking, self.listed = best[1], False
        return Decision(ord("Q"), "quaff", f"a breath of {best[0]} in view: drink {best[1][len('Potion of '):]}")

    def remembered_bursts(self, obs: Observation, lasting: bool = False,
                          assume: frozenset[str] = frozenset()) -> list[int]:
        """The bursts of the breathers seen on the level in BREATHER_MEMORY
        steps, each divided by the resistance to its own elements."""
        return [burst // self.elements_div(obs, elements, lasting, assume)
                for elements, (step, burst) in self.level.breathers.items() if obs.step - step < BREATHER_MEMORY]

    def shake_paralyzer(self, obs: Observation, view: View) -> None | Decision:
        """Beside a creature whose touch has paralysed the bot (learned from
        "the X paralyzes you."): out of its reach before anything else, as a
        player without Free Action does; every turn beside it may be several more
        paralysed. A level-35 Priest woke at 67/253 beside an Iridescent
        Beetle and an Umber Hulk, drank a potion and prayed there, and was
        paralysed again and beaten to death (C64 Balrog, 2026-11-07). The
        long escapes first, then Phase Door, then a step out of its reach."""
        if obs.dlvl == 0 or not self.paralyzers or "Magi" in self.jewel_names.get("Amulet", ""):
            return None   # Free Action (the Amulet of the Magi): no blow paralyses
        glyphs = knowledge.glyphs_of()
        bad = {g for name in self.paralyzers for g in glyphs.get(name, ())}
        near = [p for p, c in view.creatures.items() if c.glyph in bad and chebyshev(p, view.pos) == 1]
        if not near:
            return None
        why = f"beside the '{view.creatures[near[0]].glyph}' that paralyses"
        magic = self.magic
        far = self.far_escape(obs, why)
        if far is not None:
            return far
        for spell in (TELEPORT_SELF, PORTAL):
            if magic.can(obs, spell):
                return Decision(*magic.pray(spell, f"{why}: cast {spell}"))
        if self.phase and obs.step >= self.blind_until:
            self.picking, self.listed = PHASE, False
            self.level.phased = obs.step
            return Decision(ord("R"), "phase", f"{why}: read Phase Door")
        if magic.can(obs, PHASE_DOOR):
            self.level.phased = obs.step
            return Decision(*magic.pray(PHASE_DOOR, f"{why}: cast Phase Door"))
        for (dx, dy), key in DIRS.items():
            x, y = view.pos[0] + dx, view.pos[1] + dy
            if view.passable(x, y, avoid_monsters=True) and all(chebyshev(p, (x, y)) > 1 for p in near):
                return Decision(key, "retreat", f"{why}: out of its reach")
        return None

    def note_breathers(self, obs: Observation, view: View) -> None:
        """The biggest turn's worth of breath or spells of a creature in view
        (``turn_burst`` unresisted: a fast breather breathes twice), by the
        elements that divide it, and when: ``rest`` keeps the bot resting
        until it could take one."""
        if not obs.dlvl:
            return
        burst, infos, moves = knowledge.spell_burst(), knowledge.breath_info(), knowledge.moves()
        for c in view.creatures.values():
            key = (c.glyph, c.level)
            if key not in burst:
                continue
            times = max(1.0, moves.get(key, 1.0))
            breath, elements, other = infos.get(key, (0, frozenset(), burst[key]))
            for kind, most in ((elements, breath), (frozenset(), other)):
                if most:
                    self.remember_burst(obs, kind, int(most * times))

    def remember_burst(self, obs: Observation, elements: frozenset[str], burst: int) -> None:
        held = self.level.breathers.get(elements)
        self.level.breathers[elements] = (obs.step, max(burst, held[1] if held else 0))
        held_all = self.level.breather
        self.level.breather = (obs.step, max(burst, held_all[1] if held_all else 0))

    def note_breath(self, obs: Observation, view: View, loss: int, element: str | None = None) -> None:
        """A breath just taken, ``loss`` HP: the next is as big
        (``breath_guard``), and one that could kill from full HP makes the
        level one to leave (``leave_deadly``), seen or not. A level-34
        Half-Troll Priest took 232 of 245 from an Ancient Blue Dragon in the
        dark, prayed Cure Medium Wounds four times where it stood, and the
        second breath killed it (C64 Balrog, 2026-11-07)."""
        # A breath taken under the Resist Heat timer was a third of the next:
        # a level-36 Priest took 50 resisted from an unseen Mature Black
        # Dragon, explored on at 121/264, and its next breath did 153 (C64
        # Balrog, 2026-11-08). Kept as the lasting resistance leaves it, and as
        # a breather about (rest heals first).
        # Resistance is by element (monster_cast_breath): an element not known
        # was not resisted.
        raw = loss * (self.resist_div(obs, element) if element else 1)
        loss = raw // (self.resist_div(obs, element, lasting=True) if element else 1)
        self.level.breath = (obs.step, loss)
        self.remember_burst(obs, frozenset({element}) if element else frozenset(), raw)
        if loss >= BREATH_LETHAL * obs.mhp and self.level.deadly is None:
            self.level.deadly = view.pos

    def breath_guard(self, obs: Observation, view: View) -> Decision | None:
        """A caster in view whose biggest breath or spell alone could kill
        (BREATH_LETHAL of the HP): not one more turn in its sight. ``danger``
        weighs a spell by how often it is cast, a Young Red Dragon's 96-HP
        breath as about 38: a level-32 Dwarf Priest healed to 89/166 and
        walked on in its sight, and a level-33 Paladin prayed Cure Light
        Wounds at 89/304 beside an Ancient White Dragon; one breath each
        (2026-11-07). A potion that lifts the HP over it, else the farthest
        escape at hand, else a step out of its line of sight."""
        if obs.dlvl == 0:
            return None
        lethal = {p: self.turn_burst(c, obs) for p, c in view.creatures.items()
                  if not self.stationary(c) and self.turn_burst(c, obs) >= BREATH_LETHAL * obs.hp
                  and self.sees(view, view.pos, p)}
        breath = self.level.breath
        if lethal:
            worst = max(lethal.values())
            who = f"the '{view.creatures[max(lethal, key=lethal.get)].glyph}'"
        elif breath is not None and obs.step - breath[0] < UNSEEN_BREATH_STEPS and breath[1] >= BREATH_LETHAL * obs.hp:
            # Breathed on from out of sight: as big again, from who knows where.
            worst, who = breath[1], "a breath unseen"
        else:
            return None
        for potion in sorted(POTION_HEAL, key=POTION_HEAL.get, reverse=True):
            held = self.clw if potion == CLW else self.strong.get(potion, 0)
            if held and obs.hp + POTION_HEAL[potion] > worst / BREATH_LETHAL and obs.hp + POTION_HEAL[potion] <= obs.mhp:
                self.picking, self.listed = potion, False
                return Decision(ord("Q"), "quaff", f"{who} could breathe {worst}: drink {potion[len('Potion of '):]} Wounds")
        magic = self.magic
        far = self.far_escape(obs, f"{who} could breathe {worst}")
        if far is not None:
            return far
        for spell in (TELEPORT_SELF, PORTAL):
            if magic.can(obs, spell):
                return Decision(*magic.pray(spell, f"{who} could breathe {worst}: cast {spell}"))
        hidden = []
        for (dx, dy), key in DIRS.items() if lethal else ():   # unseen: no sight line to step out of
            x, y = view.pos[0] + dx, view.pos[1] + dy
            if view.passable(x, y, avoid_monsters=True) and not any(self.sees(view, (x, y), p) for p in lethal):
                hidden.append((min(chebyshev(p, (x, y)) for p in lethal), key))
        if hidden:
            return Decision(max(hidden)[1], "retreat", f"{who} could breathe {worst}: out of its sight")
        if self.phase and obs.step >= self.blind_until:
            self.picking, self.listed = PHASE, False
            self.level.phased = obs.step
            return Decision(ord("R"), "phase", f"{who} could breathe {worst}: read Phase Door")
        if magic.can(obs, PHASE_DOOR):
            self.level.phased = obs.step
            return Decision(*magic.pray(PHASE_DOOR, f"{who} could breathe {worst}: cast Phase Door"))
        return None

    def scout(self, obs: Observation, view: View) -> Decision | None:
        """Deep, with nothing in view: Detect Evil (or Detect Monsters) on
        arrival and every SCOUT_EVERY steps, as a player looks before
        walking into the dark. Six of the first seven deaths of a level-34
        Half-Troll Priest's copies were dragons; one breathed from a dark
        room it never saw, at 224/245 HP (2026-11-07)."""
        if obs.dlvl < SCOUT_FROM or self.level.deadly is not None or self.threats(view):
            return None
        if self.level.scouted_at is not None and obs.step - self.level.scouted_at < SCOUT_EVERY:
            return None
        magic = self.magic
        spell = next((name for name in (DETECT_EVIL, DETECT_MONSTERS) if magic.can(obs, name)), None)
        if spell is None:
            return None
        self.level.scouted_at = obs.step
        return Decision(*magic.pray(spell, f"scout the level: {spell}"))

    def turn_burst(self, c: Creature, obs: Observation, lasting: bool = False,
                   assume: frozenset[str] = frozenset()) -> int:
        """The most a creature's spells or breath can do before the bot's
        next turn: one burst (``knowledge.spell_burst``, resistance divided
        out) for each move it makes a turn. Ancient dragons are fast: a
        level-37 Priest at 186/296 HP fought an Ancient White Dragon whose
        234-HP breath looked survivable and was breathed on twice, 468, in
        one turn (C64 Balrog, 2026-11-08)."""
        one = self.burst_now((c.glyph, c.level), obs, lasting, assume)
        return int(one * max(1.0, knowledge.moves().get((c.glyph, c.level), 1.0)))

    def leave_deadly(self, obs: Observation, view: View) -> Decision | None:
        """A creature seen or detected that could kill from full HP with one
        breath or spell (BREATH_LETHAL of max HP): leave the level, by the
        stairs underfoot, the nearest known ones, or Word of Recall. Ancient
        dragons breathed 200-230 at a 245-HP Priest (2026-11-07)."""
        if obs.dlvl == 0:
            return None
        for p, c in view.creatures.items():
            if self.turn_burst(c, obs, lasting=True) >= BREATH_LETHAL * obs.mhp:
                self.level.deadly = p
        if self.level.deadly is None:
            return None
        here = view.type_at(*view.pos)
        if here == TYPE_STAIRS_UP or (here == TYPE_STAIRS_DN and self.deeper_ok(obs)):
            return Decision(ord("<") if here == TYPE_STAIRS_UP else ord(">"), "leave",
                            "a creature here could kill in one breath: take the stairs")
        stairs = view.stairs_up() | (view.stairs_down() if self.deeper_ok(obs) else set())
        far = view.path_steps(stairs, avoid_monsters=True) if stairs else None
        if not self.recalling and self.recall and obs.step >= self.blind_until \
                and (far is None or far > LEAVE_WALK_STEPS):
            # A long walk in the open is the danger: Word of Recall first, then
            # the stairs if they come sooner. A level-36 Priest walked 40 steps
            # toward stairs from an Ancient White Dragon (234 of 259) and was
            # breathed on once its resistance ran out (C64 Balrog, 2026-11-08).
            self.picking, self.listed = RECALL, False
            return Decision(ord("R"), "recall", "a creature here could kill in one breath: read Word of Recall")
        if self.recalling and (far is None or far > LEAVE_WALK_STEPS):
            return None
        step = view.step_toward(stairs, avoid_monsters=True) if stairs else None
        if step is not None and step != (0, 0):
            return Decision(DIRS[step], "leave", "a creature here could kill in one breath: to the stairs")
        return None

    def grave(self, obs: Observation, view: View) -> bool:
        """The next turn's expected damage is GRAVE_DANGER of the HP or more."""
        return self.danger(view.pos, view, obs) >= GRAVE_DANGER * obs.hp

    def hurt_out(self, obs: Observation, view: View) -> Decision | None:
        """Badly hurt with no healing potion left: Word of Recall, or the
        stairs underfoot. 31 of 75 deaths at level 24+ explored, searched or
        groped under half their HP, most with nothing left to drink
        (2026-11-06)."""
        # With no escape at hand (Phase Door, Portal, a Staff of Teleportation)
        # sooner: Word of Recall comes 15-35 turns after it is read. Level-32
        # Balrog Paladins and a Priest, their mana spent and no Phase Door
        # bought, fought on to 7-11% of their HP and died (2026-11-07).
        share = HURT_OUT_HP if self.can_phase(obs) else HURT_OUT_HP_NO_ESCAPE
        if obs.dlvl == 0 or obs.hp >= share * obs.mhp:
            return None
        if (self.clw or any(self.strong.values())) and self.danger(view.pos, view, obs) == 0:
            return None   # nothing can hurt it: ``quaff`` rested instead
        # Potions held that ``quaff`` (first) found too weak for the danger
        # are no healing: a level-34 Priest carried 80 Cure Light Wounds,
        # each a sixteenth of its HP, and fought on to its death (2026-11-07).
        if self.recall and not self.recalling and obs.step >= self.blind_until:
            self.picking, self.listed = RECALL, False
            return Decision(ord("R"), "recall", f"HP {obs.hp}/{obs.mhp}, no potions: read Word of Recall")
        here = view.type_at(*view.pos)
        if here in (TYPE_STAIRS_UP, TYPE_STAIRS_DN) and (here == TYPE_STAIRS_UP or self.deeper_ok(obs)):
            return Decision(ord("<") if here == TYPE_STAIRS_UP else ord(">"), "retreat",
                            f"HP {obs.hp}/{obs.mhp}, no potions: take the stairs")
        return None

    def dark_step(self, view: View, goals: set[Pos]) -> tuple[int, int] | None:
        """First step of a path that takes unknown squares for floor, but
        those a move into went nowhere (``LevelMemory.felt``)."""
        known = view.types
        view.types = [0 if t == UNKNOWN else t for t in known]
        for x, y in self.level.felt:
            view.types[y * view.cols + x] = WALL
        try:
            return view.step_toward(goals, avoid_monsters=True)
        finally:
            view.types = known

    def grope(self, view: View) -> Decision | None:
        """Nothing left but frontier squares that revealed nothing (light
        reaches only the next square): feel into their unknown neighbours,
        once each. A wall is a bump (``note_bump``); floor shows the way on
        (M4 round 43: seed 1003 rested 1,500 steps beside an open door and
        starved)."""
        def unknown_next(pos: Pos) -> list[tuple[Pos, int]]:
            return [((pos[0] + dx, pos[1] + dy), key) for (dx, dy), key in DIRS.items()
                    if view.inside(pos[0] + dx, pos[1] + dy)
                    and view.type_at(pos[0] + dx, pos[1] + dy) == UNKNOWN
                    and (pos[0] + dx, pos[1] + dy) not in self.level.groped]
        here = unknown_next(view.pos)
        if here:
            target, key = here[0]
            self.level.groped.add(target)
            return Decision(key, "grope", "feel into the dark")
        edges = {p for p in view.frontier(traps=True) if unknown_next(p)}
        return self.move(view, view.step_toward(edges, avoid_monsters=True) if edges else None,
                         "grope", "walk to an unexplored edge to feel into")

    # -- prompt layer -------------------------------------------------------------

    def prompt(self, obs: Observation) -> Decision:
        if obs.mode == Mode.CHARGEN:
            if obs.stage == "stats":
                self.rolls += 1
                if self.rolls < ROLL_LIMIT and not roll_good(obs.rows, self.goal.race, self.goal.klass):
                    return Decision(ord("R"), "prompt", f"reroll stats (roll {self.rolls})")
            race, klass = self.goal.character
            return Decision(Game.chargen_key(obs, self.name, race, klass), "prompt", f"chargen {obs.stage}")
        if obs.mode == Mode.ITEM and self.dropping:
            return self.drop_prompt(obs)
        if obs.mode == Mode.ITEM and obs.stage == "list" and self.magic.listing_books:
            return Decision(*self.magic.book_list(obs))
        if self.picking is not None and obs.mode == Mode.ITEM:
            return self.pick_item(obs)   # a -more- first keeps the pick pending
        if obs.mode == Mode.DISMISS and self.listing_equipment:
            self.listing_equipment = False
            worn = self.read_equipment(obs.rows)
            self.jewels.update(self.read_jewels(obs.rows))
            if worn is not None:
                self.armour.update(worn)
                self.armour_hits = 0
                return Decision(KEY_SPACE, "prompt", f"armour worn: AC {sum(worn.values())} by the list")
        if obs.mode == Mode.DISMISS:
            return Decision(KEY_SPACE, "prompt", f"dismiss {obs.stage}")
        if obs.mode == Mode.DEATH:
            return Decision(KEY_SPACE, "prompt", "death flow")
        if obs.mode == Mode.STORE:
            return self.store(obs)
        if obs.mode == Mode.SPELL:
            return Decision(*self.magic.prompt(obs))
        if obs.mode == Mode.GENOCIDE:
            key, letter = self.genocide_key()
            return Decision(key, "prompt", f"genocide {letter}")
        if obs.mode == Mode.DIRECTION and self.pending is not None:
            key, self.pending = self.pending, None
            return Decision(key, "prompt", "direction for the pending action")
        if self.pending_item is not None and "which" in obs.rows[0]:
            key, self.pending_item = self.pending_item, None
            return Decision(key, "prompt", "first matching item")
        if obs.mode == Mode.ITEM:
            return Decision(KEY_RUNSTOP, "prompt", f"cancel item prompt ({obs.stage})")
        return Decision(KEY_RUNSTOP, "prompt", f"cancel unknown prompt {obs.stage}".strip())

    def genocide_key(self) -> tuple[int, str]:
        """Genocide's letter (2026-11-05: answered, not cancelled): the kind
        seen on this level that could do the most damage in a turn, as a
        player names what threatens them; 'p' when none was seen. The key is
        the one core/game_loop_helpers.s recall_key_to_screen_code reads:
        a-z unshifted ($41-$5A), A-Z shifted ($C1-$DA)."""
        letters = {g: t for g, t in self.level.kinds.items() if g.isascii() and g.isalpha() and t > 0}
        letter = max(letters, key=lambda g: (letters[g], g)) if letters else "p"
        return (ord(letter.upper()) if letter.islower() else 0xC1 + ord(letter) - ord("A")), letter

    def store(self, obs: Observation) -> Decision:
        """Buy food, then a lantern and oil, at the General Store. Never haggle:
        cheap items are a Y/N buy, and an offer of the asking price is taken."""
        if obs.stage == "buy_which" and self.store_letter is not None:
            letter, self.store_letter = self.store_letter, None
            return Decision(ord(letter.upper()), "shop", f"buy item {letter}")
        if obs.stage == "buy_confirm":
            self.count_purchase()
            return Decision(ord("Y"), "shop", "confirm the price")
        if obs.stage == "haggle":
            return self.offer(obs)
        if obs.stage == "message":
            if any("Your pack is full." in row for row in obs.rows):
                self.pack_full = True          # drop something, then shop again (drop_prompt)
                self.refused_at = self.at_store
            if self.bought is not None:
                self.credit(self.bought, -1)   # the counted purchase did not happen
            self.bought = None
            self.leave_store(obs)   # cannot afford it or pack full: stop buying
            return Decision(KEY_SPACE, "shop", "acknowledge the store message")
        self.bought, self.typing = None, []
        done = {TEMPLE: self.potions_done, BLACK_MARKET: self.market_done, ARMOURY: self.armoury_done,
                WEAPONSMITH: self.weapons_done, ALCHEMIST: self.alchemist_done,
                MAGIC_SHOP: self.magic_done}.get(self.at_store, self.shopped)
        held = re.search(r"Gold: (\d+)", obs.rows[16])   # a store screen shows no status line
        market_gear = self.at_store == BLACK_MARKET and held is not None and int(held.group(1)) >= MARKET_GEAR_GOLD
        gear_first = None
        if obs.stage == "menu" and not done and market_gear:
            # Rich: the Black Market's enchanted armour and weapons first
            # (bought armour tops out near AC 19; 2026-11-06), then its
            # Word of Recall as before.
            gear_first = self.gear_pick(obs) or self.jewel_pick(obs)
            if gear_first is not None:
                self.store_letter, self.buying = gear_first
                self.gear_bought = True
                return Decision(ord("B"), "shop", f"buy {gear_first[1]}")
        if obs.stage == "menu" and not done and self.at_store == MAGIC_SHOP and held is not None \
                and int(held.group(1)) >= JEWEL_GOLD + self.gear_reserve(obs):
            jewel = self.jewel_pick(obs)
            if jewel is not None:
                self.store_letter, self.buying = jewel
                self.gear_bought = True
                return Decision(ord("B"), "shop", f"buy {jewel[1]}")
        if obs.stage == "menu" and not done and self.at_store in (ARMOURY, WEAPONSMITH):
            missiles = self.missile_pick(obs) if self.at_store == WEAPONSMITH else None
            gear = self.gear_pick(obs)
            if self.goal.klass in MISSILE_FIRST:
                pick = missiles or gear
            else:
                # A Warrior's melee weapon first, a launcher from what is left:
                # buying the crossbow first left a level-15 Half-Troll Warrior
                # wielding its starting Dagger (M7 queue, 2026-10-31).
                pick = gear or missiles
            if pick is not None:
                self.store_letter, self.buying = pick
                # Ammunition is no gear (a launcher is): arrows bought on every
                # visit reset the gear trip's gold and wait, and a level-25
                # Half-Orc with 27,000 gold went up every 5,000 steps (M8,
                # 2026-11-02).
                self.gear_bought = self.gear_bought or pick is gear or any(
                    pick[1].startswith(name) for name in LAUNCHERS)
                return Decision(ord("B"), "shop", f"buy {pick[1]}")
        elif obs.stage == "menu" and not done:
            gold = re.search(r"Gold: (\d+)", obs.rows[16])
            for want in self.shopping_list(int(gold.group(1)) if gold else None):
                for row in obs.rows[3:15]:
                    match = STORE_ITEM.match(row)
                    if match and match.group(2).startswith(want) and \
                            (gold is None or int(match.group(3)) <= int(gold.group(1))) and \
                            not (want in AMMO_AVERAGE and int(match.group(3)) > AMMO_MAX_GOLD) and \
                            not (want.startswith(("Wand of", "Staff of")) and want not in RECHARGEABLE
                                 and gold is not None
                                 and int(match.group(3)) > int(gold.group(1)) - self.gear_reserve(obs)):
                        self.store_letter, self.buying = match.group(1), match.group(2)
                        if want in FOODS:
                            self.shop_buys += 1
                        return Decision(ord("B"), "shop", f"buy {match.group(2)}")
        self.leave_store(obs)
        return Decision(ord("Q"), "shop", f"leave the store ({obs.stage})")

    def general_worth_it(self, obs: Observation) -> bool:
        """The General Store sells something wanted (food, light, oil), and
        there is more gold than at the last visit that bought nothing."""
        here, self.at_store = self.at_store, GENERAL_STORE
        try:
            wanted = any(w.startswith((*FOODS, LANTERN, OIL, TORCH)) for w in self.shopping_list(self.gold(obs)))
        finally:
            self.at_store = here
        return wanted and self.gold(obs) > self.general_gold

    def leave_store(self, obs: Observation) -> None:
        """The Alchemist is done once left; the General Store keeps its food
        and light bookkeeping (``end_visit``)."""
        if self.at_store == TEMPLE:
            self.potions_done = True
        elif self.at_store == BLACK_MARKET:
            self.market_done = True
        elif self.at_store == ALCHEMIST:
            self.alchemist_done = True
        elif self.at_store == MAGIC_SHOP:
            self.magic_done = True
        elif self.at_store == ARMOURY:
            self.armoury_done = True
        elif self.at_store == WEAPONSMITH:
            self.weapons_done = True
        else:
            self.general_gold = -1 if self.general_bought else self.gold(obs)
            self.general_bought = False
            self.end_visit(obs)

    def reopen_refused(self) -> None:
        """The store whose sale a full pack refused is open again this visit."""
        store, self.refused_at = self.refused_at, None
        if store == TEMPLE:
            self.potions_done = False
        elif store == BLACK_MARKET:
            self.market_done = False
        elif store == ALCHEMIST:
            self.alchemist_done = False
        elif store == MAGIC_SHOP:
            self.magic_done = False
        elif store == ARMOURY:
            self.armoury_done = False
        elif store == WEAPONSMITH:
            self.weapons_done = False

    def end_visit(self, obs: Observation) -> None:
        """Shopping is over for this visit, however it ended (round 20: a
        refused purchase skipped this and hopped forever)."""
        if self.shopped:
            return
        self.shopped = True
        if self.out_of_cures(obs):
            # Should the Temple have none either, not straight back up for them.
            self.resupply_after = obs.step + RESTOCK_WAIT
        if not self.supplies_low():
            self.hops = 0
        elif self.hops < RESTOCK_HOPS:
            self.hops += 1   # the store had no food or light: hop to DL1 and back
        else:
            # Still nothing: keep playing a while instead (round 5).
            self.hops, self.resupply_after = 0, obs.step + RESTOCK_WAIT

    def shopping_list(self, gold: int | None = None) -> list[str]:
        """Store items worth buying now, most important first. ``gold``, when
        the store shows it, limits flasks to throw to what the Temple's and
        the Alchemist's shortfalls leave spare."""
        wants: list[str] = []
        # Early trips are shallow: eight rations, the gold for flasks and
        # potions (M5b round 49: with stores stocking five at a time, a
        # level-1 Dwarf left town with 15 rations and five flasks).
        if self.shop_buys < FOOD_PER_VISIT and self.food < self.food_max():
            # A Slime Mold is a third of a ration in a whole slot: only near
            # the reserve (M4 round 57: rations only once the reserve was
            # made bought nothing when the store had none, and 8 starved).
            wants = list(FOODS) if self.food < self.food_reserve() + 2 else [FOODS[0]]
        if not (self.lamp or self.lamp_packed) and not (self.clvl < EARLY_LEVELS and self.torches >= TORCH_RESERVE):
            # Early, the kit's torches light the first trips and a lantern's
            # 40 gp is thirteen flasks to throw: a level-1 Priest bought
            # armour, a Morningstar and a lantern, then one flask, and died to
            # a Kobold (M5b round 47, VMS prices).
            wants.append(LANTERN)
        if self.torches < TORCH_RESERVE:
            wants.append(TORCH)   # backup light (M4: seed 1007 played 3,400 steps in the dark)
        committed = (max(0, self.clw_reserve() - self.clw) * CLW_GOLD
                     + max(0, self.recall_reserve() - self.recall) * RECALL_GOLD)
        early = self.clvl < EARLY_LEVELS and self.oil < OIL_RESERVE + OIL_EARLY
        if self.oil < OIL_RESERVE or early or (self.oil < OIL_RESERVE + OIL_THROW
                                               and gold is not None and gold >= committed + OIL_GOLD):
            # Lantern fuel, a missile fear cannot stop (M4: Poltergeist), and
            # 2d6 at whatever approaches: 10 gp a flask against 50 for a Cure
            # Light Wounds that heals as much (M5a: Halflings and Elves lost
            # melee with DL1 Kobolds). Flasks to throw only from gold the
            # potions and scrolls do not need: the General Store comes first,
            # and a Half-Troll that spent it there starved without Word of
            # Recall (M5a round 1). Early (``EARLY_LEVELS``), a few to throw
            # come first anyway, as a player buys them: 2d6 a flask kills a
            # Kobold in two before it is in reach, and the reserve kept for
            # potions and Word of Recall left level-1 characters only the
            # lantern's flasks (M5b round 13: 8 of 13 deaths in melee on DL1-2,
            # about four flasks thrown a character).
            wants.append(OIL)
        if self.clw < self.clw_reserve():
            wants.append(CLW)
        if self.strong_wanted():
            wants += [CCW, CSW]   # the best the Temple has and the gold allows
        if "strong_potions" in self.goal.tactics and self.clvl >= STRONG_LEVEL and self.neutralize < NEUTRALIZE_RESERVE:
            wants.append(NEUTRALIZE)
        if self.restore_due and not self.restoration:
            wants.append(RESTORATION)
        if self.max_dlvl >= SCOUT_FROM and self.resist_heat < RESIST_RESERVE:
            wants.append(RESIST_HEAT)
        if self.max_dlvl >= SCOUT_FROM and self.resist_cold < RESIST_RESERVE:
            wants.append(RESIST_COLD)   # frost breath since 2026-11-08 (white dragons)
        if gold is not None and self.enchant_wanted(gold):
            wants.append(ENCHANT_ARMOR)
        if self.recall < self.recall_reserve():
            wants.append(RECALL)
        if self.phase < self.phase_reserve():
            wants.append(PHASE)
        if self.teleports < self.teleport_reserve():
            wants.append(TELEPORT_SCROLL)
        if self.launcher is not None and self.ammo < AMMO_RESERVE:
            wants.append(LAUNCHERS[self.launcher][0])   # 1-2 gp a shot
        if self.at_store == TEMPLE and self.book_next is not None and self.book_next not in MAGE_BOOKS:
            wants.insert(0, store_name(self.book_next))   # a caster's prayers first (maintainer, 2026-10-25)
        if self.at_store == MAGIC_SHOP:
            # Only a Mage's next book there (M5f: Mages learned one book and
            # cast only Magic Missile; maintainer, 2026-10-27: "mages are
            # only successful by using their full spell repertoire"), and
            # something for an unconfirmed Recharge to work on.
            return ([store_name(self.book_next)] if self.book_next in MAGE_BOOKS else []) + (
                list(RECHARGEABLE) if self.recharge_wanted() else []) + self.wands_wanted()
        if self.at_store == BLACK_MARKET:
            # Word of Recall; rich (maintainer, 2026-11-07: "max out"), what
            # the other stores seldom stock too: strong potions, Phase Door,
            # Enchant Armor, Resist Heat and Cold.
            rich = gold is not None and gold >= MARKET_GEAR_GOLD
            keep = (RECALL, PHASE, TELEPORT_SCROLL, CCW, CSW, ENCHANT_ARMOR, RESIST_HEAT, RESIST_COLD) if rich else (RECALL,)
            wants = [w for w in wants if w in keep]
            if rich:
                # Every stat short of 18/100, Constitution and the fighting
                # stats first (GAIN_POTIONS order otherwise).
                order = sorted(GAIN_POTIONS, key=lambda k: GAIN_POTIONS[k] not in ("CO", "ST", "DX"))
                wants += [k for k in order if self.stat_now.get(GAIN_POTIONS[k], 0) < STAT_MAXED]
        elif self.at_store == ALCHEMIST:
            wants = [w for w in wants if w in (RECALL, PHASE, TELEPORT_SCROLL, RESTORATION, ENCHANT_ARMOR)]
        return wants

    def stats(self, obs: Observation) -> tuple[int, int]:
        """Strength and dexterity from the status lines (18/xx as 18 + xx/10)."""
        found = {}
        for row in obs.rows[19:24]:
            for name, base, extra in STAT.findall(row):
                found[name] = stat_value(base, extra)
        if "ST" in found:
            self.last_stats = (found["ST"], found.get("DX", 10))
        # A store screen shows no stats: the last ones seen, not a default.
        # With STR 10 assumed there, a weaker Human Priest bought a 15 lb
        # Morningstar and hit 66 times in 377 swings (M5b round 50).
        return self.last_stats

    def melee_score(self, name: str, to_dam: int, obs: Observation) -> float:
        """Expected melee damage a turn before to-hit: blows (Umoria's table,
        ``combat_calc_blows``) times the dice average plus the to-dam bonus."""
        ego = EGO_WEAPON.match(name)
        kind = knowledge.item_kinds().get(ego.group(1) if ego else name)
        if kind is None or not kind.melee:
            return 0.0
        strength, dexterity = self.stats(obs)
        hit = (kind.dice * (kind.sides + 1) / 2 + to_dam) * EGO_FACTOR.get(ego.group(2) if ego else "", 1.0)
        return knowledge.blows(strength, dexterity, kind.weight) * (hit + EGO_FLAT.get(ego.group(2) if ego else "", 0.0))

    def melee_skill(self, name: str, obs: Observation) -> int:
        """To-hit skill with weapon ``name``: the class's and race's melee
        skill and its gain a level, less Umoria's too-heavy penalty, three
        a point by which the weight passes STR x 15 (``combat_calc_melee_
        total_tohit_bonus``). A Human Priest bought heavy weapons by damage
        alone and hit DL1 Kobolds 42% of the time against 66% expected
        (M5b round 16: Kobolds 16 of 20 deaths)."""
        base, per_level = CLASS_BTH[self.goal.klass]
        skill = base + RACE_BTH[self.goal.race] + per_level * obs.clvl
        ego = EGO_WEAPON.match(name)
        kind = knowledge.item_kinds().get(ego.group(1) if ego else name)
        strength = self.stats(obs)[0]
        if kind is not None and strength < 18 and kind.weight > strength * 15:
            skill -= 3 * (kind.weight - strength * 15)
        return skill

    def melee_value(self, name: str, to_dam: int, obs: Observation) -> float:
        """Expected melee damage a turn against ``REFERENCE_AC``: blows and
        dice (``melee_score``) times the chance to hit."""
        return self.melee_score(name, to_dam, obs) * knowledge.hit_chance(self.melee_skill(name, obs), REFERENCE_AC)

    def gear_reserve(self, obs: Observation) -> int:
        """Gold kept back from gear. A level-1 Priest left town with 175 gold
        unspent, a Dagger and Leather Armour, under the 200 reserve, and died
        to DL1 Kobolds (M5b round 5); early on the General Store has already
        bought the trip's food and light. A wanted prayer book's price on top:
        a level-5 Priest reached the Temple with 172 gold against Words of
        Wisdom's 309 (M5b round 22)."""
        reserve = GEAR_RESERVE_EARLY if obs.clvl < EARLY_LEVELS else GEAR_RESERVE
        if self.goal.klass in ("mage", "priest"):
            # Potions before armour for a 6-12 HP Mage or Priest: Elf and
            # Halfling Mages spent the gold on a shield, boots and gloves,
            # left with two potions, and died to DL1 Kobolds and poison gas
            # holding none (M5f round 4; the Human, with less to spend,
            # carried five); 9-HP Gnome Priests died with none (round 12).
            reserve = max(reserve, max(0, CLW_RESERVE - self.clw) * CLW_GOLD)
        book = self.book_wanted(obs)
        return reserve + (BOOK_GOLD.get(book, 0) if book else 0)

    def recharge_wanted(self) -> bool:
        """A Recharge spell known whose effect is unseen, and nothing to cast it on."""
        return not self.rechargeable and not any(self.wands.values()) and any(
            name in self.magic.known and not self.magic.confirmed(name) for name in RECHARGE_SPELLS)

    def early_potion_gold(self, obs: Observation) -> int:
        """Gold a weak early caster keeps for Cure Light Wounds before Word of
        Recall: Elf Priests paid 160 of 238 gold for a scroll at level 1,
        took four potions down and died at level 1-4 holding none (C128,
        2026-11-04). The stairs are the way out on DL1-2."""
        if obs.clvl >= EARLY_LEVELS or self.goal.klass not in ("mage", "priest"):
            return 0
        return max(0, CLW_RESERVE - self.clw) * CLW_GOLD

    def clw_reserve(self) -> int:
        """Potions to carry: fewer while saving for a wanted prayer book."""
        return CLW_SAVING if self.book_next is not None else CLW_RESERVE

    def gear_pick(self, obs: Observation) -> tuple[str, str] | None:
        """At the Armoury or Weaponsmith: the item that most improves what is
        worn in its slot, or the weapon wielded, that the gold allows while
        keeping ``GEAR_RESERVE`` (M4 round 74: characters met Green Nagas on
        DL5-9 with the starting Dagger and AC 4, carrying thousands of gold)."""
        if self.goal.klass == "mage" and self.at_store not in (ARMOURY, BLACK_MARKET):
            # A Mage fights with Magic Missile and flasks, not its weapon: a
            # level-1 Halfling Mage bought a Tulwar and a Spear and left town
            # with two potions (M5f baseline, seed 1018).
            return None
        gold = re.search(r"Gold: (\d+)", obs.rows[16])
        budget = (int(gold.group(1)) if gold else 0) - self.gear_reserve(obs)
        if self.at_store == ARMOURY and self.weapon == STARTING_WEAPON and not self.weapons_done \
                and self.goal.klass != "mage":
            # Armour first (a Priest's first stop) leaves the price of a
            # weapon: 13 of 15 deaths at level 1-3 still held the starting
            # Dagger, the gold spent on armour (M5b round 36b).
            budget -= WEAPON_GOLD_EARLY
        # Bought this visit counts as worn: a second body armour for the slot
        # just filled is no gain (M5a: several pieces a visit now, §16).
        worn, wielded = dict(self.armour), self.weapon
        for name in self.to_wear:
            kind, change = self.gear.get(name, ("", None))
            if kind == "armour":
                slot, ac = change
                worn[slot] = max(worn.get(slot, 0), ac)
            elif kind == "weapon":
                wielded = change
        best: tuple[float, int, str, str, tuple[str, object]] | None = None
        for row in obs.rows[3:15]:
            match = STORE_ITEM.match(row)
            if match is None or int(match.group(3)) > budget:
                continue
            letter, name, price = match.group(1), match.group(2), int(match.group(3))
            armour = GEAR_ARMOUR.match(name) if self.at_store in (ARMOURY, BLACK_MARKET) else None
            kind = knowledge.item_kinds().get(armour.group(1)) if armour else None
            if kind is not None and kind.category in ARMOUR_SLOTS:
                ac = int(armour.group(2)) + int((armour.group(3) or "0").replace(" ", ""))
                gain, change = ac - worn.get(kind.category, 0), ("armour", (kind.category, ac))
            elif self.at_store == ARMOURY or (self.at_store == BLACK_MARKET and self.goal.klass == "mage"):
                continue
            else:
                weapon = GEAR_WEAPON.match(name)
                to_dam = int(weapon.group(3)) if weapon and weapon.group(3) else 0
                base = weapon.group(1) if weapon else name
                gain = self.melee_value(base, to_dam, obs) - self.melee_value(*wielded, obs)
                change = ("weapon", (base, to_dam))
            if gain > 0 and (best is None or (gain, -price) > (best[0], best[1])):
                best = (gain, -price, letter, name, change)
        if best is None:
            return None
        self.gear[best[3]] = best[4]
        return best[2], best[3]

    def offer(self, obs: Observation) -> Decision:
        """Type the asking price as the offer: the store takes it at once."""
        prompt = " ".join(obs.rows[19:23])
        if "Take it?" in prompt:
            return Decision(ord("Y"), "shop", "take the final offer")
        if not self.typing:
            ask = re.search(r"Asks (\d+) gp", prompt)
            if ask is None:
                return Decision(ord("Q"), "shop", "no asking price shown: cancel")
            self.typing = [ord(c) for c in ask.group(1)] + [KEY_RETURN]
        key = self.typing.pop(0)
        if key == KEY_RETURN:
            self.count_purchase()
        return Decision(key, "shop", "offer the asking price")

    def count_purchase(self) -> None:
        if self.bought is None and self.buying is not None:
            self.general_bought = self.general_bought or self.at_store == GENERAL_STORE
            self.bought = self.buying
            self.credit(self.buying, 1)

    def credit(self, item: str, n: int) -> None:
        """Count an item gained (n=1) or a counted one not gained after all (n=-1)."""
        if item.startswith(("Wand of", "Staff of")):
            name, charges = item.split(" (")[0].strip(), CHARGES.search(item)
            self.wands[name] = max(0, self.wands.get(name, 0) + n * (int(charges.group(1)) if charges else 1))
        if item.startswith(RECHARGEABLE):
            self.rechargeable = n > 0
            for name in RECHARGE_SPELLS:
                self.on_item_after.pop(name, None)   # something to recharge now: try again
        if item.startswith(FOODS):
            self.food += n * (SLIME if item.startswith("Slime") else 1)
            self.no_food = self.no_food and n < 0
        elif item.startswith(LANTERN):
            self.lamp_packed = n > 0
        elif item.startswith(OIL):
            self.oil += n
        elif item.startswith(RESTORATION):
            self.restoration += n
        elif item.startswith(tuple(GAIN_POTIONS)):
            kind = next(k for k in GAIN_POTIONS if item.startswith(k))
            self.gains[kind] = max(0, self.gains.get(kind, 0) + n)
        elif item.startswith(ENCHANT_ARMOR):
            self.enchant_scrolls += n
        elif item.startswith(TORCH):
            self.torches += n
        elif item.startswith(CLW):
            self.clw += n
        elif "strong_potions" in self.goal.tactics and item.startswith(tuple(self.strong)):
            kind = next(k for k in self.strong if item.startswith(k))
            self.strong[kind] = max(0, self.strong[kind] + n)
        elif item.startswith(RECALL):
            self.recall += n
        elif item.startswith(NEUTRALIZE):
            self.neutralize = max(0, self.neutralize + n)
        elif item.startswith(RESIST_HEAT):
            self.resist_heat = max(0, self.resist_heat + n)
        elif item.startswith(RESIST_COLD):
            self.resist_cold = max(0, self.resist_cold + n)
        elif item.startswith(IDENTIFY_SCROLL):
            self.identify_scrolls = max(0, self.identify_scrolls + n)
        elif item.startswith(PHASE):
            self.phase += n
        elif item.startswith(TELEPORT_SCROLL):
            self.teleports = max(0, self.teleports + n)
        elif item.startswith(tuple(LAUNCHERS)):
            if n > 0:
                self.launcher = next(name for name in LAUNCHERS if item.startswith(name))
                self.ammo = 0   # another launcher's ammunition does not fit it
            elif self.launcher is not None and item.startswith(self.launcher):
                self.launcher = None   # a spare one dropped leaves the one carried
        elif item.startswith(tuple(AMMO_AVERAGE)):
            if self.launcher is not None and item.startswith(LAUNCHERS[self.launcher][0]):
                self.ammo += n
        elif book_of(item) is not None:
            if n > 0:
                self.books_owned.add(book_of(item))
                self.magic.new_book()
            else:
                self.books_owned.discard(book_of(item))   # the counted purchase did not happen
        elif item in self.gear and n > 0:
            self.to_wear.append(item)
        elif item in self.gear and item in self.to_wear:
            self.to_wear.remove(item)   # the counted purchase did not happen

    def expects_item_prompt(self) -> bool:
        """An item prompt (or its list) is one the brain asked for: a pick, a
        drop of junk, or the book prompt's list (M5e: every junk drop was
        filed as an unknown prompt)."""
        return self.picking is not None or self.pending_item is not None or self.dropping \
            or self.magic.listing_books

    def sync_counts(self, rows: list[str], scope: str) -> None:
        """Counts kept from messages drift (a scroll burnt, a potion
        shattered); a listing is the truth. ``scope`` is what the listing
        holds, by the command that showed it: "scrolls" (read), "potions"
        (quaff) or "all" (drop). A level-27 Priest walked for supplies and
        stood in the dark 2.4 million steps with two Words of Recall its
        count said it lacked (C64 Balrog, 2026-11-06)."""
        listed: list[tuple[str, int]] = []
        for row in rows:
            match = PACK_ITEM.match(row)
            if match:
                count = PACK_COUNT.match(row)
                listed.append((re.sub(r"^an? ", "", match.group(2).strip()), int(count.group(1)) if count else 1))
        if not listed:
            return

        def held(prefix: str) -> int:
            return sum(n for name, n in listed if name.startswith(prefix))
        if scope in ("scrolls", "all"):
            self.recall, self.phase, self.identify_scrolls = held(RECALL), held(PHASE), held(IDENTIFY_SCROLL)
            self.teleports = held(TELEPORT_SCROLL)
            self.enchant_scrolls = held(ENCHANT_ARMOR)
        if scope in ("potions", "all"):
            self.clw, self.neutralize, self.restoration = held(CLW), held(NEUTRALIZE), held(RESTORATION)
            self.resist_heat, self.resist_cold = held(RESIST_HEAT), held(RESIST_COLD)
            self.gains = {k: held(k) for k in GAIN_POTIONS if held(k)}
            for kind in self.strong:
                self.strong[kind] = held(kind)

    def pick_item(self, obs: Observation) -> Decision:
        """Answer an item prompt (wear, throw): list the items, then pick by name."""
        rows = obs.rows[1:]
        kind = self.picking_kind()
        if kind is not None and obs.stage == "list":
            self.sync_counts(rows, kind)   # the read or quaff list: every scroll or potion carried
        if self.picking in (TORCH, LANTERN) and any(PACK_ITEM.match(row) for row in rows):
            # The light with the most turns left: a burnt-out one stays in
            # the pack, and wearing it left the bot blind with no "gone out"
            # message to come (M5b round 43, seeds 1020 and 1006). An empty
            # lantern can still be refueled; an empty torch is useless.
            fuelled = [(int(m.group(1)), row) for row in rows
                       if (m := LIGHT_TURNS.search(row)) and PACK_ITEM.match(row)
                       and PACK_ITEM.match(row).group(2).startswith(self.picking)
                       and (int(m.group(1)) > 0 or self.picking == LANTERN)]
            rows = [max(fuelled)[1]] if fuelled else []
            if fuelled:
                # The wear message drops the fuel when it runs past 40
                # columns ("You are wearing a Wooden Torch."): keep the
                # picked one's, and count the spares the pack really holds
                # (M5b round 44: a 27-charge torch was taken for 4,000 turns,
                # with no spare left, and the bot went dark far from town).
                self.picked_light = max(fuelled)[0] * LIGHT_CHARGE_TURNS
                if self.picking == TORCH:
                    self.torches = sum(t >= SPARE_TORCH_CHARGES for t, _ in fuelled)
        for row in rows:   # a full pack lists a-v down to row 22 (M4: item u was missed)
            match = PACK_ITEM.match(row)
            # Unknown flavours carry their article in the name ("a Blue Potion"):
            # the pick-up message's name has it stripped (2026-11-04).
            if match and re.sub(r"^an? ", "", match.group(2)).startswith(re.sub(r"^an? ", "", self.picking)):
                if self.picking == OIL:
                    self.oil = max(0, self.oil - 1)   # thrown: counted once actually picked
                elif self.picking == CLW:
                    self.clw = max(0, self.clw - 1)
                elif self.picking in self.strong:
                    self.strong[self.picking] = max(0, self.strong[self.picking] - 1)
                elif self.picking == PHASE:
                    self.phase = max(0, self.phase - 1)
                elif self.picking == TELEPORT_SCROLL:
                    self.teleports = max(0, self.teleports - 1)
                elif self.picking == NEUTRALIZE:
                    self.neutralize = max(0, self.neutralize - 1)
                elif self.picking == RESIST_HEAT:
                    self.resist_heat = max(0, self.resist_heat - 1)
                elif self.picking == RESIST_COLD:
                    self.resist_cold = max(0, self.resist_cold - 1)
                elif self.picking == ENCHANT_ARMOR:
                    self.enchant_scrolls = max(0, self.enchant_scrolls - 1)
                    self.equip_checked = self.equip_checked and self.enchant_scrolls > 0   # all read: the list again
                elif self.picking in GAIN_POTIONS:
                    self.gains[self.picking] = max(0, self.gains.get(self.picking, 0) - 1)
                elif self.picking == RESTORATION:
                    self.restoration = max(0, self.restoration - 1)
                    self.restore_due, self.stat_max = False, {}   # the stats as they now read are the baseline
                elif self.picking == RECALL:
                    self.recall = max(0, self.recall - 1)
                    self.recalling = True
                elif self.picking.startswith(IDENTIFY_SCROLL):
                    self.identify_scrolls = max(0, self.identify_scrolls - 1)
                elif self.picking.startswith(("Wand of", "Staff of")):
                    charges = CHARGES.search(row)
                    left = int(charges.group(1)) if charges else self.wands.get(self.picking, 1)
                    self.wands[self.picking] = max(0, left - 1)   # this use spends one
                elif self.picking in self.gear:
                    # Counted as worn only once it is in the pack to put on:
                    # a refused purchase never got there (M4: a haggled price
                    # over the gold).
                    kind, change = self.gear.pop(self.picking)
                    if kind == "weapon":
                        self.weapon = change
                    elif kind == "jewel":
                        self.jewels[change[0]] = change[1]
                        self.jewel_names[change[0]] = self.picking
                    else:
                        self.armour[change[0]] = change[1]
                self.picking, self.picking_next = self.picking_next, None   # a second prompt to come, or none
                if self.picking is not None:
                    self.listed = False
                return Decision(ord(match.group(1).upper()), "prompt", f"pick {match.group(2).strip()}")
        if not self.listed and ITEM_PROMPT.search(obs.rows[0]):
            self.listed = True
            return Decision(ord("?"), "prompt", "list the items")
        self.forget_picking()
        return Decision(KEY_RUNSTOP, "prompt", "item to pick not listed: cancel")

    def picking_kind(self) -> str | None:
        """The read or quaff list ``picking`` is chosen from, if either."""
        if self.picking is None:
            return None
        if self.picking.startswith("Scroll") or unknown_kind(self.picking) == "scroll":
            return "scrolls"
        if self.picking.startswith("Potion") or unknown_kind(self.picking) == "potion":
            return "potions"
        return None

    def nothing_carried(self) -> None:
        """The command found none of its kind ("You have nothing there.",
        no prompt): no scroll or potion of any name is carried. A level-28
        Rogue's count kept a Word of Recall it lacked; it read it every 2,000
        steps for a million steps on DL1, lightless (C64 Balrog, 2026-11-07)."""
        kind = self.picking_kind()
        if kind == "scrolls":
            self.recall = self.phase = self.teleports = self.identify_scrolls = self.enchant_scrolls = 0
        elif kind == "potions":
            self.clw = self.neutralize = self.restoration = self.resist_heat = self.resist_cold = 0
            self.gains = {}
            for name in self.strong:
                self.strong[name] = 0
        self.forget_picking()

    def forget_picking(self) -> None:
        """``picking`` is not carried: its count is 0, whatever it said."""
        if self.picking == OIL:
            self.oil = 0          # the pack has none, whatever the count said (M4 seed 1006)
        elif self.picking == TORCH:
            self.torches = 0
        elif self.picking == CLW:
            self.clw = 0
        elif self.picking in self.strong:
            self.strong[self.picking] = 0
        elif self.picking == PHASE:
            self.phase = 0
        elif self.picking == TELEPORT_SCROLL:
            self.teleports = 0
        elif self.picking == NEUTRALIZE:
            self.neutralize = 0
        elif self.picking == RESIST_HEAT:
            self.resist_heat = 0
        elif self.picking == RESIST_COLD:
            self.resist_cold = 0
        elif self.picking == RESTORATION:
            self.restoration = 0
        elif self.picking in GAIN_POTIONS:
            self.gains.pop(self.picking, None)
        elif self.picking == ENCHANT_ARMOR:
            self.enchant_scrolls = 0
        elif self.picking == RECALL:
            self.recall = 0
        elif self.picking is not None and self.picking.startswith(("Wand of", "Staff of")):
            self.wands[self.picking] = 0
        elif self.picking is not None and self.picking.startswith(IDENTIFY_SCROLL):
            # 2026-11-06: a count left above the pack's read Identify for an
            # unknown wand, found none, cancelled and asked again, 30,000
            # steps (a C128 main-queue game, no level for 150,000 steps).
            self.identify_scrolls = 0
        self.picking, self.picking_next = None, None

    # -- bookkeeping ----------------------------------------------------------------

    def identify(self, view: View, messages: str, attacker: str | None) -> None:
        """Learn what unknown glyphs are, then show that in the view.

        A look answer names the glyph it was aimed at; an attack names its
        attacker, which must be an unidentified glyph next to the player (the
        player was caught off guard). Creature names come from ``knowledge``.
        """
        names = knowledge.creature_levels()
        self.follow_moved(view)
        if self.pending_look is not None:
            target, self.pending_look = self.pending_look, None
            match = LOOK_RESULT.search(messages)
            if match:
                name = match.group(1)
                self.level.identified[target] = ("creature" if name in names else "item", name)
        if attacker is not None:
            # Only a glyph the attacker is drawn with, and only when no visible
            # creature drawn that way is already next to the player (review:
            # a dropped Ration ',' was pinned as a "Kobold").
            glyphs = knowledge.glyphs_of().get(attacker, frozenset())
            seen = {c.glyph for p, c in view.creatures.items() if chebyshev(p, view.pos) == 1}
            for pos, glyph in view.unknown.items():
                known = self.level.identified.get((pos, glyph))
                # Not a glyph in rock: a treasure vein's '$' beside Creeping
                # Coins was taken for them, and the bot attacked the wall,
                # which takes no game time, for 85,000 steps (M5a focused
                # round 12, seed 1018).
                if chebyshev(pos, view.pos) == 1 and (known is None or known[0] == "item") \
                        and glyph in glyphs and glyph not in seen \
                        and (view.type_at(*pos) in WALKABLE_TYPES or view.type_at(*pos) == UNKNOWN):
                    # An attack also overrides an item the glyph was taken
                    # for (M4 round 86: a patch looked at as "a Rock").
                    self.level.identified[(pos, glyph)] = ("creature", attacker)
        self.items_seen = {}
        for pos, glyph in list(view.unknown.items()):
            known = self.level.identified.get((pos, glyph))
            if known is not None:
                del view.unknown[pos]
                if known[0] == "creature":
                    view.creatures[pos] = Creature(glyph, names.get(known[1], 0))
                elif view.on_screen(pos):
                    self.items_seen[pos] = (glyph, known[1])

    def follow_moved(self, view: View) -> None:
        """A creature identified by its glyph keeps its name when it moves:
        its glyph gone from the square, the same glyph unidentified on exactly
        one square next to it. Otherwise a Creeping Copper Coins ('$', like
        gold) read as unknown after every step, so explore walked back beside
        it between hits (M4 round 46b: ~8 of 15 deaths)."""
        moved = {}
        for (old, glyph), known in list(self.level.identified.items()):
            if known[0] != "creature" or view.unknown.get(old) == glyph or not view.on_screen(old):
                continue
            near = [p for p, g in view.unknown.items()
                    if g == glyph and chebyshev(p, old) == 1 and (p, g) not in self.level.identified]
            if len(near) == 1:
                del self.level.identified[(old, glyph)]
                moved[(near[0], glyph)] = known
        self.level.identified.update(moved)

    def note_toughness(self, obs: Observation, attacker: str | None, messages: str) -> None:
        """A kind of creature that has cost half the bot's HP without being
        slain is tough for the next few character levels: not hunted, and
        run from early (M4 rounds 52-54: Green Nagas killed 3 a round in
        fights they won on acid and crushing)."""
        loss = 0 if self.last_hp is None else self.last_hp - obs.hp
        self.last_hp = obs.hp
        slain = SLAIN.search(messages)
        if slain:
            self.fight_loss.pop(slain.group(1), None)
        if attacker is not None and loss > 0:
            self.fight_loss[attacker] = self.fight_loss.get(attacker, 0) + loss
            if self.fight_loss[attacker] >= TOUGH_LOSS * obs.mhp:
                self.tough[attacker] = obs.clvl
                self.fight_loss[attacker] = 0

    def tough_glyphs(self, obs: Observation) -> frozenset[str]:
        glyphs = knowledge.glyphs_of()
        return frozenset(g for name, clvl in self.tough.items() if obs.clvl < clvl + TOUGH_LEVELS
                         for g in glyphs.get(name, ()))

    def remember_stationary(self, view: View) -> None:
        """A creature that never moves is still there out of sight (§14.3
        round 15); it is gone once the player stands next to its empty spot."""
        for pos, creature in view.creatures.items():
            if self.stationary(creature):
                self.level.stationary[pos] = creature
        for pos in list(self.level.stationary):
            if pos not in view.creatures and chebyshev(pos, view.pos) <= 1:
                del self.level.stationary[pos]

    def shun_stationary(self, obs: Observation, view: View, decision: Decision) -> Decision:
        """Never spend a turn standing still next to a creature that never
        moves: step off instead (M4 round 49: seed 1013, confused by a Brown
        Mold, rested and searched beside it until it killed him)."""
        if obs.dlvl == 0 or decision.key in DIRS.values() or decision.layer not in STILL_LAYERS:
            return decision
        beside = {p for p in self.hazards(view) if chebyshev(p, view.pos) == 1}
        if not beside:
            return decision
        hazards = self.hazards(view)
        for (dx, dy), key in sorted(DIRS.items()):
            x, y = view.pos[0] + dx, view.pos[1] + dy
            if view.passable(x, y, avoid_monsters=True) and all(chebyshev(h, (x, y)) > 1 for h in hazards):
                return Decision(key, "retreat", "step away from a creature that never moves")
        return decision

    def break_oscillation(self, obs: Observation, view: View, decision: Decision) -> Decision:
        """Two squares, back and forth: whatever flips the choice each step
        (a layer, a view change), going back again is no progress. Block the
        square for a while and choose again (M4 round 34: seeds 1001, 1003,
        1012 stepped A-B-A-B for hundreds of steps and died there). A longer
        circuit is no progress either: a C128 Warrior walked an 8-square lap
        toward the up stairs 2,300 times and starved (M6, seed 1002)."""
        if decision.key not in DIRS.values() or decision.layer in ("fight", "look", "prompt"):
            return decision
        # Moves only: a potion drunk between the steps put the same square in
        # the trail twice, which reads as standing still, and a Halfling
        # stepped back and forth beside a Yellow Jelly, drinking every few
        # steps, until it died (M5a round 7: 5 Yellow Jelly deaths).
        self.trail = (self.trail + [view.pos])[-OSCILLATION_STEPS:]
        self.loop_trail = (self.loop_trail + [view.pos])[-LOOP_WINDOW:]
        step = next(d for d, k in DIRS.items() if k == decision.key)
        target = (view.pos[0] + step[0], view.pos[1] + step[1])
        two_squares = (len(self.trail) == OSCILLATION_STEPS and len(set(self.trail)) == 2
                       and not any(a == b for a, b in zip(self.trail, self.trail[1:]))
                       and target in self.trail)
        circuit = (self.loop_trail.count(target) >= LOOP_VISITS
                   and len(set(self.loop_trail)) <= LOOP_SQUARES)
        if not (two_squares or circuit):
            return decision
        # Each time the same square ends a loop again, it stays blocked twice
        # as long: blocked BUMP_STEPS a time, a loop between resting and
        # exploring resumed 250,000 times and spent ten characters' whole
        # 1,000,000-step budgets (2026-11-03 A/B).
        repeats = self.level.loop_blocks[target] = self.level.loop_blocks.get(target, 0) + 1
        self.level.bumped[target] = obs.step + BUMP_STEPS * 2 ** min(repeats - 1, LOOP_BLOCK_DOUBLINGS)
        view.blocked.add(target)
        self.trail, self.loop_trail = [], []
        return self.choose(obs, view)

    def remember_glyphs(self, view: View) -> None:
        """Unidentified glyphs scroll off the screen with the viewport: keep
        them for the level, or a path past one flips each time the screen
        scrolls (M4, seed 1003: 200 steps between two squares, then
        starved). One is forgotten when its square is on screen without it."""
        for pos, glyph in view.unknown.items():
            self.level.glyphs[pos] = glyph
        for pos, glyph in list(self.level.glyphs.items()):
            if pos in view.unknown:
                continue
            if view.on_screen(pos) or (pos, glyph) in self.level.identified:
                del self.level.glyphs[pos]
            else:
                view.unknown[pos] = glyph

    def threats(self, view: View) -> set[Pos]:
        """Creatures in view that can reach the player: stationary ones only
        when adjacent."""
        return {p for p, c in view.creatures.items()
                if not self.stationary(c) or chebyshev(p, view.pos) <= 1}

    def track(self, obs: Observation, view: View) -> None:
        self.map_scale = view.cols * view.rows / C64_MAP_AREA
        if obs.dlvl != self.last_dlvl:
            if obs.dlvl == 0 or (self.climb_from is not None and obs.dlvl < self.climb_from):
                self.climb_hops, self.climb_from = 0, None   # higher than the hops began: real progress
            if obs.dlvl == 0 and self.last_dlvl is not None:
                self.equip_checked = False   # once a town visit, before the Armoury
            if self.last_dlvl == 0 and self.armoury_done and self.weapons_done:
                # Leaving town: both gear stores visited and nothing bought
                # means nothing better at this gold; gold alone is no reason
                # to come back until there is more of it (C128 catalog cycle,
                # 2026-11-02: clvl 24 with 22,000 gold recalled up every
                # 5,000 steps and bought nothing).
                self.gear_trip_gold = GEAR_TRIP_GOLD if self.gear_bought else self.gold(obs) + GEAR_TRIP_GOLD
                # 1,000 more gold came within the 5,000 steps on DL13: a
                # level-26 Gnome with 27,000 gold went up every 5,000 steps
                # and bought nothing (M8, 2026-11-02). Wait twice as long.
                self.gear_wait = GEAR_TRIP_WAIT if self.gear_bought else min(
                    2 * self.gear_wait, RESTOCK_BACKOFF_MAX * GEAR_TRIP_WAIT)
                self.gear_trip_after = obs.step + self.gear_wait
            if self.last_dlvl == 0:
                # Leaving town without Word of Recall: the next trip for it
                # waits twice as long each time (as restocking does). A
                # level-19 Paladin whose pack was full went up for one every
                # 1,500 steps, 170 refusals, down from town and back up into
                # a DL2 pocket it could not leave (C128, 2026-11-06).
                # At most two waits: with none, DL5 and below are shut
                # (``prepared``), and level-26-28 Balrog characters with
                # 300,000-500,000 gold wandered DL3-5 up to 24,000 steps a
                # wait (2026-11-06); the full pack behind the 170 refusals
                # is now emptied in town (``drop_junk``).
                if self.recall:
                    self.recall_wait = RESTOCK_WAIT
                else:
                    self.recall_trip_after = obs.step + self.recall_wait
                    self.recall_wait = min(2 * self.recall_wait, RECALL_WAIT_MAX)
                # Leaving town still short of strong potions or Phase Door:
                # the stores seldom stock them, so wait twice as long before
                # the next try. A level-25 Half-Troll on the Balrog goal
                # recalled up every 5,000 steps from DL10-17 for 22 trips,
                # walking down from DL1 each time (M8, 2026-11-02).
                if self.restock_short():
                    self.restock_wait = min(2 * self.restock_wait, RESTOCK_BACKOFF_MAX * GEAR_TRIP_WAIT)
                else:
                    self.restock_wait = GEAR_TRIP_WAIT
                self.restock_trip_after = obs.step + self.restock_wait
            self.gear_bought = False
            self.last_dlvl = obs.dlvl
            self.level = LevelMemory()
            if obs.dlvl == 0:
                self.recall_trip_after = obs.step + RESTOCK_WAIT   # one try per visit: the Alchemist may have none
                self.gear_trip_after = obs.step + GEAR_TRIP_WAIT   # the stores restock slowly
                self.restock_trip_after = obs.step + GEAR_TRIP_WAIT   # the Temple and Alchemist too
                self.book_trip_after = obs.step + RESTOCK_WAIT     # the Temple may have none
            self.shopped, self.shop_buys, self.potions_done, self.market_done = False, 0, False, False
            self.magic_done = False
            self.armoury_done = self.weapons_done = self.alchemist_done = False
            self.recalling = False
            self.max_dlvl = max(self.max_dlvl, obs.dlvl)
            self.trip_dlvl = max(self.trip_dlvl, obs.dlvl) if obs.dlvl else 0
            self.last_move = None
        known = len(view.types) - view.types.count(UNKNOWN)
        if known > self.level.known or obs.xp > self.last_xp:
            self.level.known = known
            self.level.since_progress = 0
        else:
            self.level.since_progress += 1
        self.last_xp = obs.xp
        if self.level.since_progress > STALL_STEPS and not self.level.stall_reported and obs.dlvl > 0:
            self.level.scum = self.level.stall_reported = True
            self.events.append(f"no new map or XP for {STALL_STEPS} steps on DL{obs.dlvl}; "
                               "stair-scumming")

    def move(self, view: View, step: tuple[int, int] | None, layer: str, reason: str) -> Decision | None:
        """Turn a path step into a key; doors on the path are opened or bashed
        first, and known traps disarmed first (round 23)."""
        if step is None or step == (0, 0):
            return None
        target = (view.pos[0] + step[0], view.pos[1] + step[1])
        if view.type_at(*target) == TYPE_TRAP:
            tries = self.level.disarm_attempts.get(target, 0)
            if tries < DISARM_TRIES:
                self.level.disarm_attempts[target] = tries + 1
                self.pending = DIRS[step]
                return Decision(KEY_DISARM, layer, f"{reason}: disarm the trap")
        if view.type_at(*target) == TYPE_DOOR_CLOSED:
            tries = self.level.door_attempts.get(target, 0)
            if tries >= OPEN_TRIES + BASH_TRIES:
                self.level.blocked.add(target)
                return None
            self.level.door_attempts[target] = tries + 1
            self.pending = DIRS[step]
            if tries < OPEN_TRIES:
                return Decision(ord("O"), layer, f"{reason}: open door")
            return Decision(KEY_BASH, layer, f"{reason}: bash stuck door")
        return Decision(DIRS[step], layer, reason)

    def deeper_ok(self, obs: Observation) -> bool:
        """The goal wants more depth and the character is ready for it. With
        food low it does not go deeper (but may leave town after shopping)."""
        if self.final_step(obs):
            return True   # arriving completes a depth goal: readiness and food no longer matter
        return (obs.dlvl < self.goal.target_dlvl and not self.underleveled(obs)
                and not (obs.dlvl > 0 and self.needs_resupply(obs)))

    def out_of_cures(self, obs: Observation) -> bool:
        """Early, with no Cure Light Wounds left and the gold for two: back to
        town before the next fight, the stairs a level or two away. Eleven of
        twelve Kobold deaths at level 1-4 had drunk theirs and explored on
        (C128, 2026-11-04)."""
        return obs.clvl < EARLY_LEVELS and not self.clw and self.gold(obs) >= 2 * CLW_GOLD

    def needs_resupply(self, obs: Observation) -> bool:
        """Food or light is low and a town trip could help (not right after a
        visit that found the store without it), or the character carries no
        Word of Recall and can now afford one."""
        # A caster who can pray Create Food does not climb for food.
        low = self.light_low() or (self.food_low() and not self.magic.feeds(obs)) or self.out_of_cures(obs)
        # Deep goal: out of the strong potions with the gold for more: every
        # level-16-21 death on the first potion builds had drunk all five
        # and never went back for more (M7 queue, 2026-10-31).
        # Phase Door too: a level-19 Dwarf Warrior with neither met a Stone
        # Giant in the dark and fought it to the end (same queue).
        # Not straight back after a visit: the stores seldom stock them, and
        # characters recalled up every 2,600 steps to find none (C128 catalog
        # cycle, 2026-11-02: 38 trips, 17 strong potions and 4 Phase Doors).
        restock = ("restock" in self.goal.tactics and self.restock_short()
                   and obs.step >= self.restock_trip_after
                   and self.gold(obs) >= STRONG_RESERVE * STRONG_GOLD[CSW])
        return ((low and obs.step >= self.resupply_after) or self.wants_recall(obs)
                or self.wants_gear(obs) or self.wants_book_trip(obs) or restock)

    def book_levels(self) -> tuple[int, ...] | None:
        """The level of each book's first spell for this class, if it buys books."""
        levels = BOOK_LEVELS.get(self.goal.klass)
        if levels is None and "class_books" in self.goal.tactics:
            levels = CASTER_BOOK_LEVELS.get(self.goal.klass)
        return levels

    def book_wanted(self, obs: Observation) -> str | None:
        """The next prayer book not carried whose first prayer the character's
        level reaches. Books bind a caster: a prayer is learned from and prayed
        from its book, so without Words of Wisdom a Priest past level 5 learned
        nothing (M5b round 18: 239 studies found "No new spells to learn", no
        book bought; maintainer, 2026-10-25)."""
        levels = self.book_levels()
        if levels is None:
            return None
        owned = self.books_owned | set(self.magic.books or ())   # bought, or picked up and listed
        return next((book for book, level in zip(books_for(self.goal.klass), levels)
                     if book not in owned and obs.clvl >= level), None)

    def wants_book_trip(self, obs: Observation) -> bool:
        """A wanted book and the gold for it: a town trip to the Temple."""
        book = self.book_wanted(obs)
        return (book is not None and obs.dlvl > 0 and obs.step >= self.book_trip_after
                and self.gold(obs) >= BOOK_GOLD.get(book, 0))

    def wants_recall(self, obs: Observation) -> bool:
        """No Word of Recall, gold for one, and no town visit lately: a trip
        to buy it. Recall is the way home from a sealed pocket (M4 §15.7
        item 1); a character that could not afford one on its last visit
        played 35,000 steps on DL1-2 and starved there in one (M5a round 2:
        about 7 such deaths)."""
        self.recall_trip_after = min(self.recall_trip_after, obs.step + RECALL_WAIT_MAX)   # a longer one saved before the cap
        return (not self.recall and obs.dlvl > 0 and obs.step >= self.recall_trip_after
                and self.gold(obs) >= RECALL_GOLD + GEAR_RESERVE)   # and the next trip's food and potions

    def wants_gear(self, obs: Observation) -> bool:
        """Gold enough for real armour and a while since the last town visit:
        a trip to spend it. Town trips came only for food, light or Word of
        Recall, so gold piled up below (M5a: a Half-Elf on DL5 with 1,547 gold
        and AC 7; several characters visited the Armoury once in a run), and
        Creeping Coins and nagas hit low AC hardest."""
        damaged = self.armour_hits >= ARMOUR_HITS_TRIP and self.gold(obs) >= self.gear_reserve(obs) + GEAR_TRIP_GOLD
        return obs.dlvl > 0 and (damaged or (obs.step >= self.gear_trip_after and self.gold(obs) >= self.gear_trip_gold))

    def supplies_low(self) -> bool:
        return self.food_low() or self.light_low()

    def light_low(self) -> bool:
        refill = (self.oil if self.lamp else 0) + self.torches
        # The last torch is the light home: steps undercount its burn (search
        # mode spends two turns a step, an auto-rest many), and characters went
        # dark far from town with no Word of Recall (M5b round 45: five runs).
        # The way home grows with the level's area, as food_reserve's (M6).
        # Without Word of Recall the way home is every staircase up: a
        # level-23 Warrior went dark on DL20 with none and died groping DL1
        # 49,000 steps later (C128, 2026-11-06).
        climb = 0 if self.recall else CLIMB_LIGHT * (self.last_dlvl or 0)
        if refill and climb and not self.lamp_packed:
            # With spares but no Recall, all the light carried must last the
            # climb: one spare torch felt plenty on DL14, and a level-18
            # Halfling went dark on the way up and hopped DL1-DL2 150,000
            # steps (C128, 2026-11-07).
            carried = self.light_left + self.torches * TORCH_TURNS + (self.oil * LAMP_TURNS if self.lamp else 0)
            return carried < (LIGHT_RESERVE + climb) * self.map_scale
        return ((self.light_left < (LIGHT_RESERVE + climb) * self.map_scale or not self.lamp)
                and not refill and not self.lamp_packed)

    def final_step(self, obs: Observation) -> bool:
        """One more staircase down completes a depth goal (round 12)."""
        return obs.dlvl + 1 == self.goal.target_dlvl and not self.goal.want_xp

    def food_reserve(self) -> float:
        """Rations to keep: deeper levels are a longer climb home (M4 round
        42: ~10 starved on DL3-8 with the flat reserve)."""
        # The deepest level of the trip, not the current one: climbing home
        # lowered the reserve under the food left and sent the bot back down,
        # one staircase each way per step (M4 round 55: ~4,000 level entries
        # per character).
        # DL1-2 are a staircase or two from town: one ration will do there
        # (M5b round 35: Dwarf Priests held below two rations by a store that
        # had one or two climbed back about 250 times a run and never went
        # deeper; the starvation deaths behind the scale were on DL3-8).
        # The way home grows with the level's area: on the 80-column ports'
        # 198x66 maps the C64's reserve starved 53 of 66 deaths, on DL1-2 (M6
        # C128 round m6a: "Faint" at death), and scaled by the width alone 4
        # of 6 (m6b): an up staircase not yet seen is a level's exploring away.
        if self.trip_dlvl <= SHALLOW_DLVL:
            return math.ceil(SHALLOW_FOOD_RESERVE * self.map_scale)
        return math.ceil((FOOD_RESERVE + self.trip_dlvl // FOOD_PER_DEPTH) * self.map_scale)

    def food_max(self) -> int:
        """Rations' worth to carry at most: eight on early, shallow trips, and
        more on a bigger map, where the way home is longer (M6: the Apple
        IIe's 198x66 levels starved Half-Trolls carrying the C64's eight)."""
        food_max = FOOD_EARLY_MAX if self.clvl < EARLY_LEVELS else FOOD_MAX
        return math.ceil(food_max * self.map_scale)

    def food_low(self) -> bool:
        """Below the reserve, in rations."""
        return self.no_food or self.food < self.food_reserve()

    def count_food(self, messages: str) -> None:
        if "You have no food." in messages:
            self.food = 0
        elif "You eat " in messages:
            self.food = max(0, self.food - (SLIME if "Slime" in messages else 1))
        elif "You picked up" in messages and any(f in messages for f in FOODS):
            self.food += SLIME if "Slime" in messages else 1
            self.no_food = False   # here, not only in eat: a prayer layer can come first

    def track_fear(self, messages: str) -> bool:
        """Fear as the messages report it; the last fear message on a screen
        wins. True when the screen reported fear either way."""
        afraid = max(messages.rfind("You are too afraid!"), messages.rfind("frightens you"))
        bolder = messages.rfind("You feel bolder")
        if afraid < 0 and bolder < 0:
            return False
        self.afraid = AFRAID_TURNS if afraid > bolder else 0
        return True

    def track_light(self, messages: str) -> None:
        """Light as a player follows it: rough time since it was lit, and a
        burnt-out light is gone (round 13)."""
        worn = WORN_LIGHT.search(messages)
        if "You are wearing a Brass Lantern" in messages:
            self.torches += not (self.lamp or self.dark)   # the lit torch went into the pack
            self.lamp, self.light_left, self.dark = True, LAMP_TURNS, False
        elif "You are wearing a Wooden Torch" in messages:
            self.lamp, self.light_left, self.dark = False, TORCH_TURNS, False
            self.torches = max(0, self.torches - 1)
        if worn or ("You are wearing a" in messages and self.picked_light is not None):
            # The game shows a light's fuel in charges of 30 turns. An empty
            # one never says "gone out": a lantern bought beside an empty one
            # was worn empty and the bot explored blind (M5b round 43).
            self.light_left = int(worn.group(1)) * LIGHT_CHARGE_TURNS if worn else self.picked_light
            self.dark = self.light_left == 0
            self.picked_light = None
        if "Your light is growing dim." in messages:
            # The count of steps runs long (a rest is many turns): the game's
            # warning is the truth. Searching in the dark finds little, and
            # rogues searched dark dead ends until they starved (2026-11-04).
            self.light_left = min(self.light_left, LIGHT_CHARGE_TURNS)
        if "Your light has gone out." in messages:
            # Still worn, as upstream: a lantern is refueled (the game removed
            # it until 2026-10-25), a torch is replaced.
            self.light_left, self.dark = 0, True
        if "Not using a lamp." in messages:
            self.lamp = False   # what is worn is not a lantern: stop refueling it
        if "Your lamp is refueled." in messages or "Your lamp overflows." in messages:
            self.light_left, self.dark = LAMP_TURNS, False
            self.oil = max(0, self.oil - 1)   # counted once the game confirms the flask was used
        elif "Your lamp is full." in messages:
            self.light_left = LAMP_TURNS
        if "You have no oil." in messages:
            self.oil = 0
        if "You picked up" in messages:
            self.oil += OIL in messages
            self.torches += TORCH in messages
            for name, charges in PICKED_WAND.findall(messages):
                self.wands[name] = self.wands.get(name, 0) + (int(charges) if charges else 1)
            for name in PICKED_ITEM.findall(messages):
                name = re.sub(r"^an? ", "", name)   # as the pack lists it
                if unknown_kind(name):
                    self.unknown[name] += 1
                elif name.startswith(("Potion of", "Scroll of")):
                    self.credit(name, 1)   # found: counted as bought (Cure potions, Phase Door, ...)
                elif self.jewel_better(name):
                    # A better ring or amulet: worn as one bought is (wear).
                    jewel = JEWEL_NAME.match(name.strip())
                    assert jewel is not None
                    self.gear[name] = ("jewel", (jewel.group(2), self.jewel_value(name)))
                    self.to_wear.append(name)
        for name in THIS_IS.findall(messages):
            # Identified: what it really is ("This is a Wand of Frost (5 charges).").
            if self.identifying is not None:
                self.unknown[self.identifying] = max(0, self.unknown[self.identifying] - 1)
                self.identifying = None
            self.credit(name, 1)

    def underleveled(self, obs: Observation) -> bool:
        """Readiness (§14.3 rounds 2, 18): not deeper before ``ready_level``.
        A level-1 character cannot survive one Cause Light Wounds (3d8) from a
        DL2 caster, so a player gains levels before going deeper. (A maximum
        HP bar, two of a depth's strongest spells, held level-4 Priests on DL1
        until level 6-7 and was removed in M5b round 36: maintainer, "that's
        your made up rule, doesn't make sense".)"""
        return (obs.clvl < ready_level(obs.dlvl + 1, self.goal.ready_margin, self.goal.ready_taper)
                or not self.prepared(obs, obs.dlvl + 1))

    def too_strong(self, creature: Creature, obs: Observation) -> bool:
        """Monster lore, before any fight: far more HP or armour than the
        character can wear down at its level (M4 rounds 52-62: nagas, orcs,
        skeleton orcs and coins killed most characters that fought them).
        Only for goals that hunt for experience: a diving character is
        outmatched nearly everywhere, and running from all of it halved
        reach_dl10 (M4 round 64 A/B: 13 of 40 against 22 of 40)."""
        return self.goal.want_xp and self.lore_strong(creature, obs)

    def lore_strong(self, creature: Creature, obs: Observation) -> bool:
        hp, ac = knowledge.strength().get((creature.glyph, creature.level), (0.0, 0))
        return (hp > STRONG_HP_BASE + STRONG_HP_PER_LEVEL * obs.clvl
                or ac > STRONG_AC_BASE + STRONG_AC_PER_LEVEL * obs.clvl
                or self.fight_odds(creature, obs) > FIGHT_ODDS)

    @staticmethod
    def danger(pos: Pos, view: View, obs: Observation, *, spells: bool = True) -> float:
        """Danger (maintainer, 2026-11-03): the most
        damage every creature in view could do to ``pos`` in the next turn.
        Melee at its maximum (dice x sides, no hit chance) from a creature
        beside ``pos``, times its moves a turn (core/monster_ai.s: a fast one
        acts twice); one two squares off only when it is fast enough to step
        in and still strike. Below clvl 20 a breeder's counts 2.5 times. Each
        caster's biggest spell, scaled by how often it casts: x0.4 under
        11%, x0.6 under 26%, x0.8 under 51%."""
        total = sum(Brain.creature_danger(c, chebyshev(at, pos), obs, spells=spells)
                    for at, c in view.creatures.items() if chebyshev(at, pos) <= DANGER_RANGE)
        return min(total, DANGER_CAP)

    @staticmethod
    def creature_danger(c: Creature, d: int, obs: Observation, *, spells: bool = True) -> float:
        """One creature's part of ``danger``, ``d`` squares from the square."""
        key = (c.glyph, c.level)
        m = knowledge.moves().get(key, 1.0)
        melee = sum(n * sides for _, n, sides in knowledge.attacks().get(key, ()))
        hit = melee * max(1.0, m) if d <= 1 else melee * (m - 1) if d == 2 and m >= 2 else 0.0
        if obs.clvl < 20 and key in knowledge.breeder_kinds():
            hit *= 2.5
        burst = knowledge.spell_burst()
        if spells and d >= 1 and key in burst:
            r = knowledge.spell_rate().get(key, 1.0)
            hit += burst[key] * (0.4 if r < 0.11 else 0.6 if r < 0.26 else 0.8 if r < 0.51 else 1.0)
        return hit

    def perilous(self, view: View, obs: Observation) -> set[Pos]:
        """Squares beside or one step from a creature in view whose melee
        danger exceeds PERILOUS of HP: paths avoid them while another way
        exists."""
        near = {(x + dx, y + dy) for x, y in view.creatures for dx in range(-2, 3) for dy in range(-2, 3)}
        bound = PERILOUS * max(obs.hp, 1)
        return {p for p in near if view.inside(*p) and p not in view.creatures
                and self.danger(p, view, obs, spells=False) > bound}

    def caution(self, obs: Observation, view: View) -> Decision | None:
        """Caution after healing, retreat and phasing (maintainer,
        2026-11-03): below ESCAPE_LEVEL, danger over half the HP takes the
        up stairs underfoot. Danger over CAUTION_BACK of HP from creatures
        that are all slower than the player backs away one step, to the
        safest square that is not beside a creature, not within two of a
        faster one, has at most CAUTION_SAFER of the danger here and, while
        healthy, is not the square of two steps ago (no stepping back and
        forth). Off once STALL_STEPS pass with no progress."""
        if obs.dlvl == 0 or not view.creatures or self.level.since_progress >= STALL_STEPS:
            return None
        hp = max(obs.hp, 1)
        here = self.danger(view.pos, view, obs)
        if here <= CAUTION_BACK * hp:
            return None
        if obs.clvl < ESCAPE_LEVEL and here > CAUTION_ESCAPE * hp and view.type_at(*view.pos) == TYPE_STAIRS_UP:
            return Decision(ord("<"), "caution", f"danger {here:.0f} at HP {obs.hp}: up the stairs")
        moves = knowledge.moves()
        near = [c for p, c in view.creatures.items() if chebyshev(p, view.pos) <= 2 and not self.stationary(c)]
        if not near or any(moves.get((c.glyph, c.level), 1.0) >= 1 for c in near):
            # Only from creatures slower than the player: one as fast follows
            # each step back and keeps biting while the player never strikes,
            # and no player backs off a Kobold a square at a time (2026-11-03:
            # without a leash, half the early deaths had backed away so).
            return None
        faster = {p for p, c in view.creatures.items() if moves.get((c.glyph, c.level), 1.0) > 1}
        earlier = self.positions[-3] if len(self.positions) >= 3 and obs.hp >= CAUTION_HOLD * obs.mhp else None
        ups = view.stairs_up()
        best: tuple[float, int, int] | None = None
        for (dx, dy), key in sorted(DIRS.items()):
            sq = (view.pos[0] + dx, view.pos[1] + dy)
            if sq == earlier or not view.passable(*sq, avoid_monsters=True) or sq in view.hazards:
                continue
            if any(chebyshev(sq, m) <= 1 for m in view.creatures) or any(chebyshev(sq, m) <= 2 for m in faster):
                continue
            there = self.danger(sq, view, obs)
            if there > CAUTION_SAFER * here:
                continue
            free = min((chebyshev(sq, u) for u in ups), default=0)   # ties: nearer the way up
            if best is None or (there, free) < best[:2]:
                best = (there, free, key)
        if best is None:
            return None
        return Decision(best[2], "caution", f"danger {here:.0f} at HP {obs.hp}: back away to {best[0]:.0f}")

    def prepared(self, obs: Observation, dlvl: int) -> bool:
        """Ready for ``dlvl`` beyond character level (maintainer,
        2026-11-03): the class row's maximum HP and level, two cure
        potions from DL3, Word of Recall from DL5."""
        row = PREPARED.get(PREPARED_ROW.get(self.goal.klass or "", "warrior"), PREPARED["warrior"])
        for depth, mhp, clvl in row:
            if dlvl >= depth and (obs.mhp < mhp or obs.clvl < clvl):
                return False
        if dlvl >= PREPARED_CURES_DLVL and self.clw + sum(self.strong.values()) < PREPARED_CURES:
            return False
        return not (dlvl >= PREPARED_RECALL_DLVL and not self.recall)

    def fight_odds(self, creature: Creature, obs: Observation) -> float:
        """Turns this character needs to kill ``creature`` over the turns it
        needs to kill the character, by the lore: the weapon's blows and
        dice at the character's strength (``melee_score``) and its chance to
        hit the creature's armour, against the creature's attacks and their
        chance to hit the character's armour. Above 1, the character dies
        first. The M4 thresholds judge the creature by character level alone,
        so a Human or Halfling Warrior met DL5 nagas the Half-Troll's
        strength could fight (M5a: 50 of 141 deaths)."""
        hp, ac = knowledge.strength().get((creature.glyph, creature.level), (0.0, 0))
        if not hp:
            return 0.0
        mine = self.melee_score(*self.weapon, obs) * knowledge.hit_chance(self.melee_skill(self.weapon[0], obs), ac)
        damage = lambda c: self.incoming(c, obs)
        own = damage(creature)
        if not own:
            return 0.0
        # Everything else beside the player hits too while this one is
        # fought: one pile of a Creeping Coins nest at a time looked an easy
        # fight each, and three together killed a Human from 82 HP (M5a
        # round 8: 12 coin deaths).
        others = list(self.adjacent)
        if creature in others:
            others.remove(creature)
        theirs = own + sum(damage(c) for c in others)
        if not theirs:
            return 0.0
        if mine <= 0:
            return float("inf")
        return (hp / mine) / (max(obs.hp, 1) / theirs)

    @staticmethod
    def incoming(c: Creature, obs: Observation) -> float:
        """Damage a turn ``c`` is expected to do by the lore, each attack's
        dice against its chance to hit the character's armour, times its
        moves a turn: a Black Mamba (fast, 4d4 poison) bites twice, and 45
        characters at clvl 12-18 fought one at half its damage and drank
        their potions beside it until they died (M7 queue, 2026-11-02)."""
        match = STATUS_AC.search(obs.rows[23])
        armour = int(match.group(1)) if match else 0
        tohit = knowledge.attack_tohit()
        return knowledge.moves().get((c.glyph, c.level), 1.0) * sum(
            dice * (sides + 1) / 2
            * knowledge.hit_chance((tohit[kind] if kind < len(tohit) else 0) + 3 * c.level, armour)
            for kind, dice, sides in knowledge.attacks().get((c.glyph, c.level), ()))

    @staticmethod
    def spell_threat(view: View) -> int:
        """The most the casters in view can do with one spell each (the
        lore): Novice Mages and Priests come in twos, and two casts in one
        step did 31 to a Human Priest at 22 HP (M5b round 54)."""
        burst = knowledge.spell_burst()
        return sum(burst.get((c.glyph, c.level), 0) for c in view.creatures.values())

    def under_blow(self, obs: Observation, view: View) -> bool:
        """Within one turn's worst melee from the creatures beside the
        character (the lore's dice, each at its maximum): a 12-HP Priest at
        6 HP beside a Kobold (1d6) kept fighting with four potions and the
        next bite killed it (M5b round 52; QUAFF_HP waits for 3)."""
        attacks, moves = knowledge.attacks(), knowledge.moves()
        worst = sum(max(1.0, moves.get((c.glyph, c.level), 1.0)) * dice * sides
                    for c in self.adjacent for _, dice, sides in attacks.get((c.glyph, c.level), ()))
        return 0 < obs.hp <= worst and obs.hp < obs.mhp

    def under_spell(self, obs: Observation, view: View) -> bool:
        """Hurt into reach of a caster's biggest spell in view: a level-4
        Dwarf Priest went back for a Novice Mage at 16 HP and one Cause Light
        Wounds (3d8) did 19; a Novice Priest's did 13 and then 19 (M5b round 44)."""
        return obs.hp < obs.mhp and obs.hp <= SPELL_MARGIN * self.spell_threat(view)

    def outmatched(self, creature: Creature, obs: Observation) -> bool:
        """Too strong by the lore, for any goal, yet unable to keep up with
        a walking player and with no spell or breath to shoot one: leave the
        level rather than meet it (M4 rounds 71-74: nagas, normal speed with
        20% random moves, killed 8-10 of ~20 reach_dl10 characters that died,
        fought to the end; walking away alone sent explore back to them)."""
        return (creature.glyph in knowledge.outpaced_glyphs() and creature.glyph not in knowledge.slow_glyphs()
                and not knowledge.casts(creature.glyph, creature.level) and self.lore_strong(creature, obs))

    def dangerous(self, creature: Creature, obs: Observation) -> bool:
        """``outmatched``; and on the deep goal below ``DEEP_DLVL``, any creature
        the lore says kills the character first (``fight_odds`` over 1), even
        one as fast as a walk: a level is left on sight of it, and it is fled
        and phased from at any HP. Giants at walking speed killed nine
        characters on DL15-20, fought to the end with Cure Light Wounds
        (M7 queue, 2026-10-31)."""
        return self.outmatched(creature, obs) or (
            "dangerous" in self.goal.tactics and obs.dlvl >= DEEP_DLVL and not self.stationary(creature)
            and self.fight_odds(creature, obs) > 1.0)

    def engageable(self, creature: Creature, obs: Observation) -> bool:
        return (creature.glyph not in AVOID_GLYPHS and not self.stationary(creature)
                and creature.glyph not in self.tough_glyphs(obs) and not self.too_strong(creature, obs)
                and (creature.glyph not in knowledge.slow_glyphs() or self.coins_worth_it(creature, obs))
                and creature.level <= obs.clvl + 2
                and (creature.glyph, creature.level) not in knowledge.breeder_kinds())   # never hunted: they multiply

    def coins_worth_it(self, creature: Creature, obs: Observation) -> bool:
        """Never: Creeping Coins drop their gold when killed (MON-014), but
        their poison touch lingers and a nest corners a character that
        fights one pile. M5a rounds 6-10 fought them below fight odds 0.5
        with no gain (coin deaths 9, 9, 12, 11), and walking away again lifted
        Elf ``clvl10`` from 16 to 18 (focused round 12). Kept as the one place
        to change that policy."""
        return False

    @staticmethod
    def stationary(creature: Creature) -> bool:
        """Never moves (jellies, molds, …; §14.3 round 9): walk around it,
        never fight it. It only hurts a player who stands next to it."""
        return creature.glyph in knowledge.stationary_glyphs()

    # -- layers ---------------------------------------------------------------------

    def hazards(self, view: View) -> set[Pos]:
        """Creatures that never move, in view or remembered on this level."""
        return set(self.level.stationary) | {p for p, c in view.creatures.items() if self.stationary(c)}

    def town_escape(self, obs: Observation, view: View) -> Decision | None:
        """Hurt by a town creature that is still beside the character: the
        down staircase loses it. Fought to the end, a Battle-Scarred Veteran
        killed a level-2 Dwarf Priest and a Mean-Looking Mercenary a level-9
        Human one (M5b round 48)."""
        beside = [p for p in view.creatures if chebyshev(p, view.pos) == 1]
        if not beside or obs.hp >= RETREAT_HP * obs.mhp or self.recalling:
            return None   # waiting for Word of Recall, stairs would undo the trip: fight
        if view.type_at(*view.pos) == TYPE_STAIRS_DN:
            return Decision(ord(">"), "retreat", "hurt by a town creature: take the stairs down")
        step = view.step_toward(view.stairs_down(), avoid_monsters=True)
        if step is None or step == (0, 0):
            return None
        return Decision(DIRS[step], "retreat", "hurt by a town creature: walk to the stairs down")

    def retreat(self, obs: Observation, view: View) -> Decision | None:
        """Escape by stairs (a fresh level loses the creature) when either
        badly hurt with a creature close, or not at full strength with one in view.

        A monster that steps into contact cannot attack that turn, so moving
        toward the stairs costs nothing while it follows. With no stairs known,
        running is pointless: fight on.
        """
        if obs.dlvl == 0:
            return self.town_escape(obs, view)
        threats = self.threats(view)
        # A retreat keeps going while what it ran from may still be there,
        # unseen (dark at two squares with a torch): stopping the turn nothing
        # hit sent explore straight back to it (M4 rounds 46b-47: a Green Naga
        # in the dark, coins).
        unseen = self.unseen_attack or (
            self.level.retreat_to is not None
            and obs.step < max(self.level.unseen_until, self.level.near_until))
        close = unseen or any(chebyshev(p, view.pos) <= 2 for p in threats)
        tough = self.tough_glyphs(obs)
        near = [view.creatures[p] for p in threats if chebyshev(p, view.pos) <= 2]
        flee_hp = 2.0 if any(self.dangerous(c, obs) for c in near) else \
            HUNT_HP if any(c.glyph in tough or self.too_strong(c, obs) for c in near) else RETREAT_HP
        badly_hurt = close and obs.hp < flee_hp * obs.mhp
        # Once fled, fled: a retreat under way goes on to its stairs while
        # the HP is short of hunting strength, the creature in view or not.
        # Stopped when it dropped out of sight, explore walked back toward
        # it hurt: three runs for the stairs in four were broken off, and a
        # character near the stairs (where they succeed) died far less
        # (2026-11-03 traces).
        committed = self.level.retreat_to is not None and obs.hp < HUNT_HP * obs.mhp
        if obs.dlvl == 0 or not (threats or unseen or committed) or (
                not committed and not badly_hurt and obs.hp >= HUNT_HP * obs.mhp and not (self.afraid and close)):
            self.level.retreat_to, self.level.retreat_path = None, set()
            self.level.retreat_failed = False
            return None
        # Afraid of something faster that keeps hitting: no melee, and it
        # follows a runner anyway, so any staircase is the way out, and
        # running costs nothing it would not take anyway (M4 round 35:
        # Poltergeist fear stacks +3 a hit and never wore off).
        trapped = self.afraid and close and (self.chased or unseen)
        down_ok = self.deeper_ok(obs) or trapped
        here = view.type_at(*view.pos)
        if here == TYPE_STAIRS_UP:
            return Decision(ord("<"), "retreat", "hurt with a creature close: take the up stairs")
        if here == TYPE_STAIRS_DN and down_ok:
            return Decision(ord(">"), "retreat", "hurt with a creature close: take the down stairs")
        names = knowledge.kinds_by_name()
        fast_near = "fight_fast" in self.goal.tactics and any(
            names.get(name) in {(c.glyph, c.level) for c in near} for name in knowledge.fast_creatures())
        if ((self.chased or fast_near) and not self.unseen_attack or self.level.retreat_failed) and not self.afraid:
            # A fast creature close follows a runner whether or not it struck
            # this turn: a level-16 Gnome Rogue ran from a Black Mamba on the
            # turns it missed, and drank five potions dying on the way (M7).
            # A visible faster attacker, or running did not work: fight
            # (rounds 14, 16). An unseen one cannot be fought: run (round 21).
            return None
        stairs = view.stairs_up() | (view.stairs_down() if down_ok else set())
        if self.level.retreat_to not in stairs:
            # Commit to one staircase (round 16): switching between two as
            # creatures come into view let followers catch up at each turn.
            self.level.retreat_to = next(
                (s for s in sorted(stairs, key=lambda s: chebyshev(s, view.pos))
                 if view.step_toward({s}, avoid_monsters=True, doors=False) is not None), None)
        stairs = {self.level.retreat_to} if self.level.retreat_to else set()
        step = None
        if stairs:
            step = (view.step_toward(stairs, avoid_monsters=True, doors=False, keep_clear=True)
                    or view.step_toward(stairs, avoid_monsters=True, doors=False))
            if step is not None and step != (0, 0):
                target = (view.pos[0] + step[0], view.pos[1] + step[1])
                if any(chebyshev(target, p) <= 1 for p in view.creatures) and \
                        any(chebyshev(view.pos, p) > 1 for p in view.creatures):
                    step = None   # the only way out runs into contact: fight instead
        if step is None:
            # Out of food, walking away from a slow creature only meets it
            # again on the way to the stairs: fight through (M5a round 2: 7
            # characters starved stepping between the two).
            # Never away from the blocker clear_way went to kill: it undid
            # each step toward it (2026-11-06: two C128 games, a ','). Nor
            # from the rest of its mass while it is in view: a worm mass is
            # many, and stepping off from the others undid the approach 100
            # times (2026-11-07: C64 and Apple II build queue, a level-30
            # Balrog Warrior on DL2).
            if self.out_of_food() or self.level.clear_target in view.creatures:
                return None
            return self.walk_away(view, threats - {self.level.clear_target})
        ranged = any(knowledge.casts(c.glyph, c.level) for c in view.creatures.values())
        if not (self.afraid or self.unseen_attack) and ranged:
            far = view.path_steps({self.level.retreat_to}, avoid_monsters=True, doors=False)
            if far is not None and far > RETREAT_RANGE:
                # Running that far gives a caster free shots: stand and fight
                # what can be fought instead (round 28, seed 1001). A melee
                # creature that follows spends its turns catching up (M4
                # round 34: seed 1014 fought a Black Naga to the death).
                self.standing = True
                return None
        self.level.retreat_path.add(view.pos)
        if (view.pos[0] + step[0], view.pos[1] + step[1]) in self.level.retreat_path and not trapped:
            # Doubling back: creatures block every way to the stairs in turn (round 16).
            self.level.retreat_failed = True
            return None
        # A retreat begun runs to the stairs: a follower out of the light
        # for NEAR_STEPS ended it, and auto-rest waited for a Large Brown
        # Snake or a centipede to catch up (M5f baseline: ~17 deaths, one
        # Elf Ranger bitten at each of three rests on the way).
        self.level.near_until = max(self.level.near_until, obs.step + NEAR_STEPS)
        return Decision(DIRS[step], "retreat", "hurt: run for the nearest stairs")

    def crowded(self, obs: Observation, view: View) -> Decision | None:
        """On a staircase with several creatures close (a Creeping Coins nest
        beside the arrival stairs), take the stairs either way: a fresh level
        beats fighting a crowd, and a down staircase leads straight to an up
        one (M4 round 88: seed 1017 walked off its stairs into a coin nest)."""
        here = view.type_at(*view.pos)
        if obs.dlvl == 0 or here not in (TYPE_STAIRS_UP, TYPE_STAIRS_DN):
            return None
        close = [c for p, c in view.creatures.items()
                 if chebyshev(p, view.pos) <= CROWD_RANGE and not self.stationary(c)]
        if len(close) >= CROWD_COUNT:
            key = ord("<") if here == TYPE_STAIRS_UP else ord(">")
            return Decision(key, "retreat", f"{len(close)} creatures close: take the stairs")
        # One creature the character would lose to, closing on the stairs it
        # stands on: a fresh level beats the fight (M5b round 4: level-1
        # Priests and Paladins, 14-16 HP, died to DL1 Kobolds 16 times). Up,
        # or down only when deeper is fine.
        strong = [c for c in close if self.lore_strong(c, obs)]
        if strong and (here == TYPE_STAIRS_UP or self.deeper_ok(obs)):
            key = ord("<") if here == TYPE_STAIRS_UP else ord(">")
            return Decision(key, "retreat", f"'{strong[0].glyph}' too strong: take the stairs")
        return None

    def shun(self, obs: Observation, view: View) -> Decision | None:
        """Early (``EARLY_LEVELS``), a creature the character would lose to
        (``lore_strong``) is not met at all: from a staircase take it, or walk
        to a staircase it can reach before the creature. About four runs a
        suite died at level 1-2 on DL1, mostly to Kobolds the lore already
        called too strong, which the crowd rule only escapes within three
        squares of the stairs (M5b rounds 36b-41: 15-17 such deaths a round)."""
        if obs.dlvl == 0 or obs.clvl >= EARLY_LEVELS:
            return None
        strong = {p: c for p, c in view.creatures.items()
                  if not self.stationary(c) and self.lore_strong(c, obs)}
        if not strong:
            return None
        nearest, pos = min((chebyshev(p, view.pos), p) for p in strong)
        glyph = strong[pos].glyph
        here = view.type_at(*view.pos)
        if here == TYPE_STAIRS_UP or (here == TYPE_STAIRS_DN and self.deeper_ok(obs)):
            return Decision(ord("<") if here == TYPE_STAIRS_UP else ord(">"), "retreat",
                            f"'{glyph}' too strong while early: take the stairs")
        if nearest < 2:
            return None   # already in contact: fight or the hurt retreat decides
        stairs = view.stairs_up() | (view.stairs_down() if self.deeper_ok(obs) else set())
        steps = view.path_steps(stairs, avoid_monsters=True) if stairs else None
        if steps is None or steps >= nearest:
            return None
        return self.move(view, view.step_toward(stairs, avoid_monsters=True), "retreat",
                         f"'{glyph}' too strong while early: walk to the stairs")

    def out_of_food(self) -> bool:
        return self.no_food or self.food <= 0

    @staticmethod
    def walk_away(view: View, threats: set[Pos], *, known_slow: bool = False) -> Decision | None:
        """No stairs to run for, but every close threat is slower than the
        player: step away from them (M4 round 35: seed 1008 fought a nest of
        Creeping Copper Coins down to 3 HP). ``known_slow``: the caller has
        judged them slow by name (M5f)."""
        close = {p for p in threats if chebyshev(p, view.pos) <= 2}
        # One that never moves (a mold) is the slowest of all: a level-26
        # Gnome Warrior, too afraid to strike, stood beside a Green Mold and a
        # Yellow Worm mass searching until the mold killed it (C128 Balrog
        # queue, 2026-11-05). Out of its reach is away from it for good.
        still = {p for p in close if view.creatures[p].glyph in knowledge.stationary_glyphs()}
        moving = close - still
        # By kind, not glyph: an Iron Golem is slow and a Ghoul drawn the
        # same is not, so a level-25 Halfling fought a golem it could not
        # hurt to the death, no stairs known (M8, 2026-11-02).
        if not close or (not known_slow and any((view.creatures[p].glyph, view.creatures[p].level)
                                                not in knowledge.slow_kinds() for p in moving)):
            return None
        here = min(chebyshev(p, view.pos) for p in close)
        here_moving = min((chebyshev(p, view.pos) for p in moving), default=99)
        in_reach = any(chebyshev(p, view.pos) <= 1 for p in still)
        best = None
        for (dx, dy), key in DIRS.items():
            x, y = view.pos[0] + dx, view.pos[1] + dy
            if view.passable(x, y, avoid_monsters=True):
                far = min(chebyshev(p, (x, y)) for p in close)
                clear = not any(chebyshev(p, (x, y)) <= 1 for p in still)
                far_moving = min((chebyshev(p, (x, y)) for p in moving), default=99)
                if (far > here or (in_reach and clear and far_moving >= here_moving)) \
                        and (best is None or (clear, far) > best[0]):
                    best = ((clear, far), key)
        return None if best is None else Decision(best[1], "retreat", "walk away from a slower creature")

    def look(self, obs: Observation, view: View) -> Decision | None:
        """Look at the nearest unidentified glyph that is first on one of the
        eight lines from the player (free: no game turn). Once per spot."""
        for pos, glyph in sorted(view.unknown.items(), key=lambda kv: chebyshev(kv[0], view.pos)):
            step = self.line_to(view, pos)
            if step is None or (view.pos, pos) in self.level.looked:
                continue
            between = {(view.pos[0] + step[0] * i, view.pos[1] + step[1] * i)
                       for i in range(1, chebyshev(pos, view.pos))}
            if between & set(self.items_seen):
                # A look reports the first thing on the line: an identified
                # item in front would be named instead (M4 round 86: seed 1005
                # filed a White Mushroom patch as "a Rock" and stood beside it).
                continue
            self.level.looked.add((view.pos, pos))
            self.pending = DIRS[step]
            self.pending_look = (pos, glyph)
            return Decision(KEY_LOOK, "look", f"identify '{glyph}' at {pos}")
        return None

    @staticmethod
    def line_to(view: View, target: Pos, *, missile: bool = False) -> tuple[int, int] | None:
        """Unit step toward ``target`` when it is the first thing a look along
        that line would reach (only known floor in between). A ``missile`` (a
        bolt, shot or flask) also needs ``target`` itself open: a creature on
        a secret door, drawn in the wall, stops one short, as VMS
        ``fire_bolt`` strikes only on ``fopen`` squares. A level-1 Elf Mage
        cast 14 Magic Missiles at a Kobold standing in a secret door beside it
        and died there (M5f round 10, seed 1012)."""
        if missile and view.type_at(*target) not in WALKABLE_TYPES and view.type_at(*target) != UNKNOWN:
            return None
        dx, dy = target[0] - view.pos[0], target[1] - view.pos[1]
        if (dx, dy) == (0, 0) or not (dx == 0 or dy == 0 or abs(dx) == abs(dy)):
            return None
        step = ((dx > 0) - (dx < 0), (dy > 0) - (dy < 0))
        x, y = view.pos[0] + step[0], view.pos[1] + step[1]
        while (x, y) != target:
            if (x, y) in view.creatures or (x, y) in view.unknown or view.type_at(x, y) != 0:
                return None
            x, y = x + step[0], y + step[1]
        return step

    def swat(self, obs: Observation, view: View) -> Decision | None:
        """A fragile creature that never moves (a mushroom patch, 1 HP) beside
        the player dies to one blow; walking past it means a paralysing spore
        at every step (M4 round 36: seed 1020 near stairs ringed with them).
        So does a weak Floating Eye (VMS: 3d6 HP): beside it the player is
        paralysed again every turn whether or not it is attacked, and other
        creatures feed meanwhile (M4 round 78: seeds 1026, 1040 fought
        Creeping Coins beside an eye until dead)."""
        if obs.dlvl == 0 or self.afraid:
            return None
        if "swat_yield" in self.goal.tactics and obs.hp < QUAFF_HP * obs.mhp and (
                self.clw or any(self.strong.values())):
            # ``quaff`` first: a level-15 Half-Elf Mage swatted a Bloodshot Eye
            # from 56 HP to death holding fifteen potions (M7 queue, 2026-10-31).
            return None
        bound = STRONG_HP_BASE + STRONG_HP_PER_LEVEL * obs.clvl
        for pos, creature in sorted(view.creatures.items()):
            if chebyshev(pos, view.pos) != 1:
                continue
            if (self.stationary(creature) and creature.glyph in knowledge.fragile_glyphs()) or (
                    creature.glyph in AVOID_GLYPHS
                    and knowledge.strength().get((creature.glyph, creature.level), (0.0, 0))[0] <= bound):
                self.last_attack = (pos, creature.glyph)
                return Decision(DIRS[(pos[0] - view.pos[0], pos[1] - view.pos[1])], "fight",
                                f"swat the '{creature.glyph}' beside the player")
        return None

    def throw(self, obs: Observation, view: View) -> Decision | None:
        """Fear blocks melee, not throwing: throw a Flask of Oil (2d6) at the
        nearest creature in line (round 22). The lantern keeps one flask unless
        spare torches back it up (M4 round 35). Before running (M4 round 32):
        a fast attacker follows a runner.

        Not afraid, a flask beyond the lantern's reserve goes at a creature
        worth one (``OIL_WORTH_HP`` by the lore) while it approaches, 2 to
        ``THROW_RANGE`` squares off: damage before it reaches the player, for
        characters whose melee is weak (M5a)."""
        if obs.dlvl == 0:
            return None
        early = obs.clvl < EARLY_LEVELS
        # Early, flasks are the weak character's best attack: the lantern
        # keeps one, and an adjacent foe is burnt rather than meleed when a
        # flask beats the weapon. Round 37 did this at every level: 12 deaths
        # at level 1-3 against 15-17 in the rounds around it, but about 20
        # flasks thrown a run drained the gold and food later (M5b round 41).
        reserve = EARLY_LANTERN_OIL if early else OIL_RESERVE
        keep = (1 if self.lamp and not self.torches else 0) if self.afraid else \
            (reserve if self.lamp or self.lamp_packed else 0)
        if self.oil <= keep:
            return None
        for pos in sorted(self.threats(view), key=lambda p: chebyshev(p, view.pos)):
            creature = view.creatures[pos]
            step = self.line_to(view, pos, missile=True)
            if step is None or chebyshev(pos, view.pos) > THROW_RANGE or self.stationary(creature):
                continue
            if not self.afraid and not self.worth_oil(creature, obs):
                continue
            if not self.afraid and chebyshev(pos, view.pos) < 2 and not (early and self.melee_weak(obs)):
                continue
            self.picking, self.listed, self.pending = OIL, False, DIRS[step]
            self.aimed = (pos, creature.glyph)
            why = "afraid" if self.afraid else "approaching"
            return Decision(KEY_THROW, "throw", f"{why}: throw oil at '{creature.glyph}'")
        return None

    def aim(self, obs: Observation, view: View) -> Decision | None:
        """An attack wand at a creature in line (maintainer, 2026-11-04):
        one too strong for melee, a dangerous one, or any while hurt, and for
        a caster whatever its spells cannot spare the mana for. The wand that
        kills in the fewest shots, the weakest of those (the big ones wait).
        After ``invoke``: a Mage's spells come first while the mana lasts."""
        wands = [w for w in ATTACK_WANDS if self.wands.get(w, 0) > 0]
        if obs.dlvl == 0 or not wands:
            return None
        mana_out = self.magic.caster(obs) and not any(self.magic.spare(obs, n) for n in MAGE_ATTACKS)
        for pos in sorted(self.threats(view), key=lambda p: chebyshev(p, view.pos)):
            creature = view.creatures[pos]
            step = self.line_to(view, pos, missile=True)
            if step is None or chebyshev(pos, view.pos) > FIRE_RANGE or self.stationary(creature):
                continue
            breeders = knowledge.breeder_kinds()
            if (creature.glyph, creature.level) in breeders:
                # A bolt on one breeder is a charge spent on what breeds back
                # (Blue Worm masses, lice: 2026-11-04); a ball on a clump of
                # them is what the ball is for (maintainer, 2026-11-04).
                clump = sum(1 for p, c in view.creatures.items()
                            if (c.glyph, c.level) in breeders and chebyshev(p, pos) <= 2)
                balls = [w for w in wands if w in BALL_WANDS]
                if clump < BALL_BREEDERS or not balls:
                    continue
                wand = min(balls, key=ATTACK_WANDS.get)   # the weakest ball does for breeders
                self.picking, self.listed, self.pending, self.last_aimed = wand, False, DIRS[step], wand
                self.aimed = (pos, creature.glyph)
                return Decision(KEY_AIM, "aim", f"aim the {wand} at {clump} '{creature.glyph}'")
            if not (self.lore_strong(creature, obs) or self.dangerous(creature, obs) or mana_out
                    or obs.hp < RETREAT_HP * obs.mhp):
                continue
            hp = knowledge.strength().get((creature.glyph, creature.level), (0.0, 0))[0] or 1.0
            wand = min(wands, key=lambda w: (math.ceil(hp / ATTACK_WANDS[w]), ATTACK_WANDS[w]))
            self.picking, self.listed, self.pending, self.last_aimed = wand, False, DIRS[step], wand
            self.aimed = (pos, creature.glyph)
            return Decision(KEY_AIM, "aim", f"aim the {wand} at '{creature.glyph}'")
        return None

    def can_identify(self) -> bool:
        """The Identify spell known, or a Scroll of Identify carried."""
        return IDENTIFY in self.magic.known or self.identify_scrolls > 0

    def unknown_kept(self, name: str) -> bool:
        """An unknown potion or scroll (tried when safe), or an unknown wand
        or staff while it can be identified; never an unknown ring yet."""
        kind = unknown_kind(name)
        return kind in ("potion", "scroll") or (kind in ("wand", "staff") and self.can_identify())

    def identify_items(self, obs: Observation, view: View) -> Decision | None:
        """An unknown wand or staff, identified with the Identify spell or a
        Scroll of Identify when nothing threatens (maintainer, 2026-11-04):
        an attack wand or a Staff of Teleportation is then kept and used."""
        target = next((n for n, c in self.unknown.items() if c > 0 and unknown_kind(n) in ("wand", "staff")), None)
        if target is None or self.threats(view) or obs.step < self.blind_until:
            return None
        if self.magic.can(obs, IDENTIFY):
            self.picking, self.listed, self.identifying = target, False, target
            return Decision(*self.magic.pray(IDENTIFY, f"identify the {target}"))
        if self.identify_scrolls > 0:
            self.picking, self.picking_next, self.listed, self.identifying = IDENTIFY_SCROLL, target, False, target
            return Decision(ord("R"), "identify", f"read a Scroll of Identify on the {target}")
        return None

    def try_unknown(self, obs: Observation, view: View) -> Decision | None:
        """Identify by use (maintainer, 2026-11-04): an unknown potion or
        scroll is drunk or read with nothing in view, HP near full, not blind
        or poisoned, as a player learns them early: a bad one (poison,
        aggravation, a curse) costs little then, and a good one (healing,
        Phase Door, Teleport, Word of Recall) is known from then on."""
        if obs.dlvl == 0 or view.creatures or self.unseen_attack or obs.hp < TRY_HP * obs.mhp \
                or obs.step < self.blind_until or self.poisoned:
            return None
        name = next((n for n, c in self.unknown.items() if c > 0 and unknown_kind(n) in ("potion", "scroll")), None)
        if name is None:
            return None
        self.unknown[name] -= 1
        self.picking, self.listed = name, False
        if unknown_kind(name) == "potion":
            return Decision(ord("Q"), "try", f"try the {name}: drink it to learn what it is")
        self.pending_item = ord("A")   # a scroll that asks for an item (Identify, an enchantment): the first
        return Decision(ord("R"), "try", f"try the {name}: read it to learn what it is")

    def wands_wanted(self) -> list[str]:
        """At the Magic Shop: an attack wand while none has charges, the best
        first, and a Staff of Teleportation while none has, or, rich, while
        its charges are under TELEPORT_CHARGES_RICH."""
        want = [] if any(self.wands.get(w, 0) for w in ATTACK_WANDS) else list(WAND_BUYS)
        keep = TELEPORT_CHARGES_RICH if self.gold_seen >= MARKET_GEAR_GOLD else 1
        return want + ([TELEPORT_STAFF] if self.wands.get(TELEPORT_STAFF, 0) < keep else [])

    def missile_pick(self, obs: Observation) -> tuple[str, str] | None:
        """At the Weaponsmith, for a class whose strength is missiles (M5d):
        a launcher better than the one carried (multiplier times its
        ammunition's average), then its ammunition. The first launcher from
        all but ``LAUNCHER_KEEP`` gold; a better one from the gold the gear
        reserve leaves."""
        if self.goal.klass not in self.goal.missile_classes:
            return None
        gold = re.search(r"Gold: (\d+)", obs.rows[16])
        gold = int(gold.group(1)) if gold else 0
        budget = gold - (LAUNCHER_KEEP if self.launcher is None else self.gear_reserve(obs))

        def value(name: str) -> float:
            ammo, mult, _ = LAUNCHERS[name]
            return mult * AMMO_AVERAGE[ammo]
        best: tuple[float, str, str] | None = None
        ammo_row: tuple[str, str] | None = None
        for row in obs.rows[3:15]:
            match = STORE_ITEM.match(row)
            if match is None:
                continue
            letter, name, price = match.group(1), match.group(2), int(match.group(3))
            launcher = next((n for n in LAUNCHERS if name.startswith(n)), None)
            if launcher is not None and price <= budget and value(launcher) > (
                    value(self.launcher) if self.launcher else 0) and (best is None or value(launcher) > best[0]):
                best = (value(launcher), letter, name)
            elif (self.launcher is not None and self.ammo < AMMO_RESERVE and price <= gold
                  and name.startswith(LAUNCHERS[self.launcher][0])):
                ammo_row = (letter, name)
        if best is not None:
            return best[1], best[2]
        return ammo_row

    def track_missiles(self, messages: str) -> None:
        """The game's answers to a shot that could not be fired."""
        if "No ammo." in messages:
            self.ammo = 0
        if "No ranged weapon." in messages:
            self.wielding_launcher = False
        if self.launcher is not None and "You picked up" in messages and LAUNCHERS[self.launcher][0] in messages:
            self.ammo += 1   # a shot that missed, collected

    def shoot(self, obs: Observation, view: View) -> Decision | None:
        """A Rogue or Ranger with a launcher (M5d): wield it while a creature
        approaches in line 3 or more squares off, fire it from 2 to
        ``FIRE_RANGE``, and wield the melee weapon again once a creature is
        beside the player (a launcher fights as bare hands, as in Umoria;
        Moria8 has no weapon swap command, so each change is a turn)."""
        if obs.dlvl == 0 or self.launcher is None:
            return None
        beside = [c for c in self.adjacent if not self.stationary(c)]
        if self.wielding_launcher and (beside or self.ammo <= 0):
            self.picking, self.listed, self.wielding_launcher = self.weapon[0], False, False
            why = "a creature beside" if beside else "out of ammunition"
            return Decision(KEY_WEAR, "shoot", f"{why}: wield the {self.weapon[0]}")
        if beside or self.ammo <= 0:
            return None
        breeders = knowledge.breeder_kinds()
        for pos in sorted(self.threats(view), key=lambda p: chebyshev(p, view.pos)):
            creature = view.creatures[pos]
            far = chebyshev(pos, view.pos)
            step = self.line_to(view, pos, missile=True)
            if step is None or far < 2 or far > min(FIRE_RANGE, LAUNCHERS[self.launcher][2]) \
                    or self.stationary(creature) or (creature.glyph, creature.level) in breeders:
                continue
            if not self.wielding_launcher:
                if far < 3:
                    continue   # no turn to spare for the change
                self.picking, self.listed, self.wielding_launcher = self.launcher, False, True
                return Decision(KEY_WEAR, "shoot", f"'{creature.glyph}' approaching: wield the {self.launcher}")
            self.pending = DIRS[step]
            self.aimed = (pos, creature.glyph)
            self.ammo -= 1
            self.missiles["shots"] += 1
            self.fired = True
            return Decision(KEY_FIRE, "shoot", f"fire the {self.launcher} at '{creature.glyph}'")
        return None

    def melee_weak(self, obs: Observation) -> bool:
        """A thrown flask (2d6) does more than a turn of melee with the weapon
        wielded (a level-1 Priest's Dagger: 1d4, one blow), each at its chance
        to hit: a weapon too heavy for the character's STR misses more (M5b
        round 44: a level-1 Human Priest with a Bastard Sword missed a Kobold
        four times running and died with three flasks unthrown)."""
        # A throw's skill: three quarters of the missile skill (Umoria
        # weaponMissileFacts, throw_calc_tohit), not the melee one: a Dwarf's
        # +15 is melee only, and Dwarf Priests threw point-blank at Kobolds
        # they would have hit harder with a Mace (M5b round 49).
        base, per_level = CLASS_BTHB[self.goal.klass]
        skill = (base + RACE_BTHB[self.goal.race] + per_level * obs.clvl) * 3 // 4
        return self.melee_value(*self.weapon, obs) < FLASK_DAMAGE * knowledge.hit_chance(skill, REFERENCE_AC)

    def worth_oil(self, creature: Creature, obs: Observation) -> bool:
        """Strong enough to be worth a flask. A slow creature only when
        meleeing it is costly (fight odds at least ``COINS_ODDS``): Creeping
        Coins, which cornered and killed characters in melee (M5a rounds
        5-9: 9-12 deaths a round), are shot as they creep up; a worm mass
        the character beats easily is walked away from or fought (M5a
        round 1: 74 flasks at 'w')."""
        if knowledge.strength().get((creature.glyph, creature.level), (0.0, 0))[0] < OIL_WORTH_HP:
            return False
        return ((creature.glyph, creature.level) not in knowledge.slow_kinds()
                or self.fight_odds(creature, obs) >= COINS_ODDS)

    def fight(self, obs: Observation, view: View) -> Decision | None:
        if (obs.dlvl == 0 and not self.attacked) or self.afraid:
            # Town creatures only fight back when provoked, but one that
            # attacks is fought (M4 round 82: seed 1023 stood waiting for Word
            # of Recall while a Battle-Scarred Veteran killed it); afraid:
            # cannot melee.
            return None
        adjacent = sorted((c.level, p) for p, c in view.creatures.items()
                          if chebyshev(p, view.pos) == 1 and c.glyph not in AVOID_GLYPHS
                          and not self.stationary(c))
        if not adjacent:
            return None
        kinds = knowledge.kinds_by_name()
        named_slow = {kinds[name] for name in knowledge.slow_names() if name in kinds and name in self.messages}
        if not self.out_of_food() and all(
                ((view.creatures[p].glyph, view.creatures[p].level) in knowledge.slow_kinds()
                 and not self.coins_worth_it(view.creatures[p], obs))
                or (view.creatures[p].glyph, view.creatures[p].level) in named_slow for _, p in adjacent):
            # Creeping coins: each poison touch stacks more poison, and they
            # cannot keep up; when hurt, fight only when cornered (M4 round
            # 45: ~5 deaths a round traded blows with them). A slow creature
            # the messages name, too: a Gnome Mage traded 40 blows with a
            # Large Brown Snake (AC 35, speed 0; its glyph and level shared
            # with the faster White Snake) and died with full mana (M5f
            # round 13).
            # Walked away and straight back beside it: it is in the way.
            # Fought when the odds favour the character, Creeping Coins
            # aside (coins_worth_it): a level-1 Ranger stepped between a
            # White Worm mass and the path to the stairs 100 times while the
            # colony poisoned it to death (2026-11-03).
            back = (len(self.trail) >= 4 and len(set(self.trail[-4:])) == 2
                    and all(view.creatures[p].glyph != "$" and self.fight_odds(view.creatures[p], obs) < FIGHT_ODDS
                            for _, p in adjacent))
            away = None if back or self.level.clear_target in view.creatures else self.walk_away(
                view, {p for _, p in adjacent} - {self.level.clear_target}, known_slow=True)
            if away is not None:
                return away
        _, (x, y) = adjacent[0]
        self.last_attack = ((x, y), view.creatures[(x, y)].glyph)
        return Decision(DIRS[(x - view.pos[0], y - view.pos[1])], "fight",
                        f"attack adjacent '{view.creatures[(x, y)].glyph}'")

    def rest(self, obs: Observation, view: View) -> Decision | None:
        """Rest to full HP (CTRL+R) whenever nothing that can reach the player
        is in view, nothing unseen has attacked lately, and there is food. Auto-rest stops by itself on damage, worse hunger, a
        message or anything coming into view, so the brain decides again.

        Short of mana too: auto-rest waits for both. A level-1 Mage has two
        Magic Missiles, and Halfling Mages (6 HP) walked on with none into
        the next Kobold and died throwing oil (M5f round 2)."""
        mp, mmp = self.magic.mana(obs)
        if obs.dlvl == 0 or self.threats(view) or self.unseen_attack or (obs.hp >= obs.mhp and mp >= mmp):
            return None
        if self.danger(view.pos, view, obs) > REST_DANGER * max(obs.hp, 1) or any(
                chebyshev(p, view.pos) <= BREEDER_REST and obs.step - seen < SLOW_AVOID
                for p, seen in self.level.breeders_seen.items()):
            if mmp and mp < CASTER_REST_MANA * mmp:
                # Out of mana with no rest to be had: leave the level, not
                # explore into what is close. A level-20 Gnome Mage at 0-5 mana
                # phased from a Guardian Naga three times, explored back to it
                # each time and died (C128, 2026-11-05).
                self.level.scum = True
            return None   # not with danger, nor near a breeder
        breather = self.level.breather
        about = max(self.remembered_bursts(obs, lasting=True), default=0)
        if about and not self.no_food and not view.creatures and about >= BREATH_LETHAL * obs.hp:
            # A breath about that could kill now: rest out of its sight first,
            # which stops when it comes back into view (breath_guard then).
            # A level-35 Priest phased from a Mature Black Dragon (160),
            # explored on at 137-152/252 and died to its next breath (C64
            # Balrog, 2026-11-07).
            # Heal at once while out of its sight: a rest is many turns, and
            # level-36 Priests rested at 32-43 HP with a hundred potions until
            # the dragon came back (C64 Balrog, 2026-11-08).
            heal = self.heal_now(obs, f"HP {obs.hp}/{obs.mhp}: a breath of {breather[1]} about")
            if heal is not None:
                return heal
            return Decision(KEY_AUTOREST, "rest", f"HP {obs.hp}/{obs.mhp}: a breath of {breather[1]} about, rest first")
        slow_near = any(obs.step - seen < SLOW_MEMORY for seen in self.level.slow_seen.values())
        if mmp and mp < CASTER_REST_MANA * mmp and not view.creatures and not self.no_food \
                and not self.unseen_attack and obs.step >= self.level.unseen_until \
                and (obs.step < self.level.near_until or slow_near):
            # A caster out of mana rests even with a creature lately close: a
            # level-24 Gnome Mage with none phased, explored back into a Giant
            # Ebony Ant and died (2026-11-05). Auto-rest stops when one shows.
            return Decision(KEY_AUTOREST, "rest", f"HP {obs.hp}/{obs.mhp} MP {mp}/{mmp}: out of mana, rest")
        if obs.step < max(self.level.unseen_until, self.level.near_until) or self.no_food or slow_near:
            if obs.dlvl >= SCOUT_FROM and obs.hp < DEEP_HEAL_HP * obs.mhp and not view.creatures:
                # No rest to be had, deep: heal before walking on, as a player
                # does. A level-37 Priest phased from Black Oozes, explored on
                # at 145/266 on DL34, and an Ancient White Dragon's breath
                # (233) killed it (C64 Balrog, 2026-11-08).
                heal = self.heal_now(obs, f"HP {obs.hp}/{obs.mhp} deep, no rest")
                if heal is not None:
                    return heal
            # A slow creature follows into the dark while auto-rest waits for
            # it (M4 round 61: Creeping Copper Coins caught a resting bot every
            # few turns, 7 deaths).
            # M4: an unseen attacker (a blinding gaze) strikes between rests;
            # starving heals nothing and costs 1 HP a turn; a creature seen
            # close may follow out of the light (Creeping Copper Coins: seeds
            # 1005, 1016 rested a turn after each retreat step and were
            # caught, rounds 35-37): move on, away from it when badly hurt
            # (M4 round 49: seed 1017 explored straight back into a Green Naga
            # at a third of its HP).
            # Only from a creature seen lately: out of food, backing away from
            # one long gone undid every step of the search for the stairs, and a
            # Paladin starved on DL3 so for 150,000 steps (C128, 2026-11-04).
            recent = obs.step < max(self.level.unseen_until, self.level.near_until) or slow_near
            if obs.hp < RETREAT_HP * obs.mhp and self.level.last_threat is not None and recent:
                away = self.step_away(view, self.level.last_threat)
                if away is not None:
                    return Decision(away, "rest", "hurt: back away from where it was")
                if slow_near and not (self.no_food or obs.step < max(self.level.unseen_until, self.level.near_until)) \
                        and chebyshev(self.level.last_threat, view.pos) >= 2:
                    # Backed away as far as it goes from a slow creature:
                    # rest, which stops when anything comes into view. Handing
                    # on to explore walked straight back toward it, then back
                    # away: ten characters spent their whole 1,000,000-step
                    # budget so at half HP (2026-11-03 A/B).
                    return Decision(KEY_AUTOREST, "rest", f"HP {obs.hp}/{obs.mhp}: backed off a slow creature, rest")
            return None
        return Decision(KEY_AUTOREST, "rest", f"HP {obs.hp}/{obs.mhp} MP {mp}/{mmp} and nothing in view")

    def heal_now(self, obs: Observation, why: str) -> Decision | None:
        """Hurt: the strongest healing potion carried, else a cure prayer;
        None at full HP or with neither."""
        if obs.hp >= obs.mhp:
            # A level-36 Priest drank Cure Serious at 259/259 against a 240
            # breath (2026-11-08).
            return None
        potion = next((k for k in sorted(POTION_HEAL, key=POTION_HEAL.get, reverse=True)
                       if (self.clw if k == CLW else self.strong.get(k))), None)
        if potion is not None and obs.step >= self.blind_until:
            self.picking, self.listed = potion, False
            return Decision(ord("Q"), "quaff", f"{why}: drink {potion[len('Potion of '):]} Wounds")
        heal = next((spell for spell in HEALS if self.magic.can(obs, spell)), None)
        if heal is not None:
            return Decision(*self.magic.pray(heal, f"{why}: pray {heal}"))
        return None

    @staticmethod
    def step_away(view: View, pos: Pos) -> int | None:
        """Key of a step that ends farther from ``pos`` than now, the farthest."""
        here = chebyshev(pos, view.pos)
        best = None
        for (dx, dy), key in sorted(DIRS.items()):
            x, y = view.pos[0] + dx, view.pos[1] + dy
            if view.passable(x, y, avoid_monsters=True):
                far = chebyshev(pos, (x, y))
                if far > here and (best is None or far > best[0]):
                    best = (far, key)
        return None if best is None else best[1]

    def take_created_food(self, obs: Observation, view: View) -> Decision | None:
        """Create Food leaves its ration on the floor underfoot, and a second
        cast replaces it: pick it up first. Left there, the food count stayed
        at 0, and a level-20 Ranger cast it every time its mana came back,
        climbed for food and hopped between DL1 and DL2 for 90,000 steps (M7
        queue, 2026-11-02)."""
        here, self.created_food = self.created_food, None
        if here != view.pos:
            return None
        return Decision(KEY_PICKUP, "collect", "pick up the food just created")

    def collect(self, obs: Observation, view: View) -> Decision | None:
        """Pick up gold and food lying in view (MON-014: kills drop them):
        gold buys potions, food and Word of Recall. Only with nothing that can
        reach the player in view, and not far off the way."""
        if obs.dlvl and self.collect_to == view.pos:
            # On it: one turn, even with something in view (a Floating Eye
            # beside the gold otherwise sent the bot back and forth for 2,900
            # steps, M4 round 46 seed 1001).
            self.collect_to = None
            self.level.collected.add(view.pos)
            return Decision(KEY_PICKUP, "collect", "pick up what lies here")
        # One asleep a way off does not stop it: a giant seen only from inside
        # a room sent a level-23 Gnome in for its gold and out again (C64
        # Balrog replay, 2026-11-06).
        awake = {p for p in self.threats(view) if not (self.still_there(p, obs) and chebyshev(p, view.pos) > 2)}
        if obs.dlvl == 0 or awake or self.unseen_attack:
            self.collect_to = None
            return None
        keep_off = view.hazards | self.hazards(view)
        def worth(glyph: str, name: str) -> bool:
            if glyph == COIN_GLYPH or name.startswith(FOODS):
                return True
            if self.launcher is not None and name.startswith(LAUNCHERS[self.launcher][0]):
                return True
            # A wand or staff already carried with charges is not taken twice.
            return not self.pack_full and (self.unknown_kept(name) or self.jewel_better(name) or self.gain_wanted(name) or (
                name.startswith(PICKUPS) and not self.wands.get(name.split(" (")[0], 0)))
        wanted = {p for p, (glyph, name) in self.items_seen.items()
                  if p not in self.level.collected and worth(glyph, name)
                  and all(chebyshev(p, h) > 1 for h in keep_off)}   # Yellow Jelly beside the gold
        reach = {p: view.path_steps({p}, avoid_monsters=True) for p in wanted}
        reach = {p: n for p, n in reach.items() if n is not None and n <= COLLECT_STEPS}
        if not reach:
            self.collect_to = None
            return None
        self.collect_to = min(reach, key=lambda p: (reach[p], p))
        walks = self.level.collect_walks[self.collect_to] = self.level.collect_walks.get(self.collect_to, 0) + 1
        if walks > COLLECT_WALKS:
            self.level.collected.add(self.collect_to)   # something keeps turning the bot back
            self.collect_to = None
            return None
        step = view.step_toward({self.collect_to}, avoid_monsters=True)
        if step is None or step == (0, 0):
            self.collect_to = None
            return None
        return Decision(DIRS[step], "collect", f"walk to the '{self.items_seen[self.collect_to][0]}' "
                                               f"at {self.collect_to}")

    def eat(self, obs: Observation, view: View) -> Decision | None:
        """Eat when hungry. Eating with no food takes no game time, so retrying
        it would loop forever: then ``resupply`` heads for town instead."""
        messages = obs.rows[0] + obs.rows[1]
        if "You have no food." in messages:
            self.no_food = True
        elif "You picked up" in messages:
            self.no_food = False
        status = obs.rows[23]
        if self.no_food or not any(word in status for word in ("Hungry", "Weak", "Faint")):
            return None
        if "Hungry" in status and any(chebyshev(p, view.pos) <= EAT_CLEAR for p in self.threats(view)):
            # Hungry is a warning, hundreds of turns before Weak: a meal can
            # wait out a creature closing in (M5a round 11: a Half-Elf
            # stopped to eat with a Rattlesnake two squares behind it and
            # died three turns later).
            return None
        self.pending_item = ord("A")
        return Decision(KEY_EAT, "eat", "hungry: eat the first food item")

    def light(self, obs: Observation, view: View) -> Decision | None:
        """Wear a bought lantern; refuel it before it burns out; replace a
        burnt-out torch with a spare."""
        if self.lamp_packed:
            self.lamp_packed, self.picking, self.listed = False, LANTERN, False
            return Decision(KEY_WEAR, "light", "wear the Brass Lantern")
        if self.lamp and self.oil and self.light_left < REFUEL_AT:
            return Decision(KEY_REFUEL, "light", "lantern running low: refuel it")
        if self.dark and self.torches:
            self.picking, self.listed = TORCH, False
            return Decision(KEY_WEAR, "light", "light gone out: wear a spare torch")
        return None

    def resupply(self, obs: Observation, view: View) -> Decision | None:
        """Head up: toward town below the food reserve, or out of a level that
        is deeper than the character is ready for (``underleveled``)."""
        too_deep = obs.clvl < ready_level(obs.dlvl, self.goal.ready_margin, self.goal.ready_taper) - 1 or (
            obs.dlvl > 1 and obs.clvl < ESCAPE_LEVEL and not self.prepared(obs, obs.dlvl))   # keep to a suitable level
        if view.type_at(*view.pos) == TYPE_STAIRS_UP and obs.clvl < ready_level(obs.dlvl, self.goal.ready_margin, self.goal.ready_taper):
            # Standing on the way back, not ready for this depth: a crowd
            # escape down arrives on an up staircase, and a level-3 Paladin
            # stayed on DL2 and died to a Novice Priest (M5b round 20, seed
            # 1019). Up costs nothing here; walking back has the slack above.
            too_deep = True
        if obs.dlvl == 0 or not (self.needs_resupply(obs) or too_deep):
            return None
        if self.final_step(obs) and (view.stairs_down() or not (
                self.no_food or self.food < FOOD_RESERVE or self.light_low())):
            # Finishing the goal beats a trip to town. The depth-scaled
            # reserve is for the climb home: one level from the goal, it sent
            # seed 1026 back up from DL9 with 4 rations, into a sealed DL8
            # pocket where it starved (M4 round 70).
            return None
        why = (("no Cure Light Wounds" if self.out_of_cures(obs) else "no Word of Recall"
                if self.wants_recall(obs) else "gold for armour")
               if not self.supplies_low() else "light low" if not self.food_low()
               else f"{self.food:.3g} food left") \
            if self.needs_resupply(obs) else f"DL{obs.dlvl} too deep for level {obs.clvl}"
        if view.type_at(*view.pos) == TYPE_STAIRS_UP:
            return Decision(ord("<"), "resupply", f"{why}: go up")
        # One staircase, kept while a way to it stands:
        # choosing the nearest again each step flipped between two.
        target = self.level.up_target
        # Kept while a way stands even past creatures: dropped whenever one
        # stood in the cautious path, two staircases far apart took turns, and
        # a level-20 Warrior walked 66 squares west and 70 back east on one
        # DL4 300 times (C128, 2026-11-07).
        if target not in view.stairs_up() or (view.step_toward({target}, avoid_monsters=True) is None
                                               and view.step_toward({target}, avoid_monsters=False) is None):
            target = None
            for up in sorted(view.stairs_up(), key=lambda u: chebyshev(u, view.pos)):
                if view.step_toward({up}, avoid_monsters=True) is not None:
                    target = up
                    break
            self.level.up_target = target
        step = self.committed_step(view, {target} if target else view.stairs_up())
        if step is None and target is not None:
            step = view.step_toward({target}, avoid_monsters=False)   # through what stands in the way
        if step is None and self.lightless() and view.stairs_up():
            # Known (Detect Doors/Stairs) but no known way there: feel the way
            # through the dark, as a player does.
            step = self.dark_step(view, view.stairs_up())
            if step is not None:
                return self.move(view, step, "resupply", f"{why}: feel the way to the up stairs")
        if not self.lightless():
            self.dark_hops = 0
        dark = self.lightless() and self.dark_hops < DARK_HOPS
        if step is None and (dark or not self.explorable(view)):
            # No way up and nothing left to explore: a down staircase arrives on
            # an up staircase to a fresh level (round 25; searching walls
            # instead starved seed 1014). In the dark too: nothing new is seen,
            # and a level-11 Mage groped and searched DL1 140,000 steps to
            # starvation beside a down staircase it knew (C128, 2026-11-04).
            # Only DARK_HOPS times: a fresh level is as dark, and a level-16
            # Mage hopped DL1-DL2 15,000 steps arriving by down stairs each
            # time; then it gropes for the way up (same day).
            if view.type_at(*view.pos) == TYPE_STAIRS_DN and not self.hopping_out():
                if dark:
                    self.dark_hops += 1
                return self.climb_hop(view, f"{why}: no way up, down to climb back")
            return self.move(view, view.step_toward(view.stairs_down(), avoid_monsters=True), "resupply",
                             f"{why}: no way up, path to the down stairs")
        return self.move(view, step, "resupply", f"{why}: path to the up stairs")

    def committed_step(self, view: View, goals: set[Pos]) -> tuple[int, int] | None:
        """The next step of the path kept to ``goals``, while its next square
        is beside the player, open and safe; else a new path, kept from here.
        Replanned at each step, the cheapest way flipped as remembered and
        perilous squares came and went: a level-15 Halfling walked toward the
        up stairs and back between x=109 and x=120 300 times on DL4, and a
        CX16 Mage did the same toward the nearest staircase (2026-11-06)."""
        route = self.level.route
        if route and route[-1] in goals:
            if view.pos in route:
                route = route[route.index(view.pos) + 1:]
            if route:
                nxt = route[0]
                if chebyshev(nxt, view.pos) == 1 and nxt not in view.perilous \
                        and view.passable(*nxt, avoid_monsters=True, doors=True):
                    self.level.route = route
                    return (nxt[0] - view.pos[0], nxt[1] - view.pos[1])
        step = view.step_toward(goals, avoid_monsters=True)
        self.level.route = list(view.last_path) if step not in (None, (0, 0)) else []
        return step

    def recall_reserve(self) -> int:
        """Word of Recall scrolls to carry. Early, one: a level-1 Paladin spent
        480 of its 570 gold on two and met DL1 Kobolds with a Dagger (M5b
        round 6); one still gets a character out of a sealed DL1-2 pocket."""
        if self.clvl < EARLY_LEVELS:
            return 1
        return RECALL_RESERVE_RICH if self.gold_seen >= MARKET_GEAR_GOLD else RECALL_RESERVE

    def shop(self, obs: Observation, view: View) -> Decision | None:
        """In town, walk into the General Store once per visit to buy food,
        then the Alchemist for Cure Light Wounds while short of them (M4).
        Early (``EARLY_LEVELS``), a weapon and armour come before the
        Alchemist and the Temple (M5b round 6)."""
        if obs.dlvl != 0:
            return None
        early = obs.clvl < EARLY_LEVELS
        if self.poisoned and not self.clw and not self.potions_done and len(view.stores) > TEMPLE \
                and self.gold(obs) >= CLW_GOLD:
            # Poison drains a point a turn in town too: a Half-Elf Rogue gassed
            # on DL1 climbed up at 8 HP with 132 gold and no potion, and died
            # on the walk to the Weaponsmith (M5 regression, seed 1002).
            store, why = TEMPLE, "poisoned with no Cure Light Wounds: walk to the Temple"
        elif early and self.goal.klass == "priest" and not self.armoury_done and len(view.stores) > ARMOURY \
                and self.gold(obs) > self.gear_reserve(obs):
            # A Priest's 12 HP and weak melee: armour before anything, the
            # kit's food and light last the first trip (maintainer, 2026-10-25:
            # "our priests should go buy some better armor right away").
            store, why = ARMOURY, "walk to the Armoury for better armour (a Priest's first stop)"
        elif early and (self.shopped or self.weapon == STARTING_WEAPON) and not self.weapons_done \
                and len(view.stores) > WEAPONSMITH and self.gold(obs) > self.gear_reserve(obs):
            # With the starting Dagger, straight after the Armoury: the General
            # Store spent the weapon's price on a lantern, oil and potions, and
            # 14 of 17 deaths at level 1-3 still held the Dagger (M5b round 39).
            store, why = WEAPONSMITH, "walk to the Weaponsmith for a better weapon (first while early)"
        elif early and self.shopped and not self.armoury_done and len(view.stores) > ARMOURY \
                and self.gold(obs) > self.gear_reserve(obs):
            store, why = ARMOURY, "walk to the Armoury for better armour (first while early)"
        elif not self.shopped and len(view.stores) > GENERAL_STORE and not self.general_worth_it(obs):
            # Nothing it sells is wanted, or the last visit could buy none
            # with this much gold: stair-scumming sends weak characters up
            # every few dozen steps, and each trip walked to the store and out
            # again empty-handed (2026-11-03).
            self.end_visit(obs)
            return self.shop(obs, view)
        elif not self.shopped and len(view.stores) > GENERAL_STORE:
            store, why = GENERAL_STORE, "walk to the General Store for food"
        elif not self.alchemist_done and len(view.stores) > ALCHEMIST and self.recall < self.recall_reserve() \
                and self.gold(obs) >= RECALL_GOLD + self.early_potion_gold(obs):
            # Word of Recall before potions: Cure Light Wounds bought first
            # left too little gold for it, and characters with none starved
            # stuck (M4 round 91: seeds 1003, 1006, 1016).
            store, why = ALCHEMIST, "walk to the Alchemy shop for Word of Recall"
        elif not self.magic_done and self.book_next in MAGE_BOOKS and len(view.stores) > MAGIC_SHOP \
                and self.gold(obs) >= BOOK_GOLD.get(self.book_next, 0):
            store, why = MAGIC_SHOP, f"walk to the Magic Shop for {self.book_next}"
        elif not self.magic_done and self.recharge_wanted() and len(view.stores) > MAGIC_SHOP \
                and self.gold(obs) >= RECHARGEABLE_GOLD + self.gear_reserve(obs):
            store, why = MAGIC_SHOP, "walk to the Magic Shop for something to recharge"
        elif not self.potions_done and len(view.stores) > TEMPLE and self.temple_worth_it(obs):
            store, why = TEMPLE, "walk to the Temple for Cure Light Wounds and Word of Recall"
        elif not self.alchemist_done and len(view.stores) > ALCHEMIST and self.restore_due \
                and not self.restoration and self.gold(obs) >= RESTORE_GOLD:
            store, why = ALCHEMIST, "walk to the Alchemy shop for Restoration (a stat drained)"
        elif not self.alchemist_done and len(view.stores) > ALCHEMIST and self.enchant_wanted(self.gold(obs)):
            store, why = ALCHEMIST, "walk to the Alchemy shop for Enchant Armor"
        elif not self.alchemist_done and len(view.stores) > ALCHEMIST and self.phase < self.phase_reserve() \
                and self.gold(obs) >= PHASE_GOLD:
            store, why = ALCHEMIST, "walk to the Alchemy shop for Phase Door"
        elif not self.alchemist_done and len(view.stores) > ALCHEMIST and self.teleports < self.teleport_reserve() \
                and self.gold(obs) >= TELEPORT_GOLD:
            store, why = ALCHEMIST, "walk to the Alchemy shop for Teleportation"
        elif not self.market_done and len(view.stores) > BLACK_MARKET and self.market_worth_it(obs):
            store, why = BLACK_MARKET, "walk to the Black Market for Word of Recall"
        elif not self.magic_done and self.jewels_wanted(obs) and len(view.stores) > MAGIC_SHOP:
            store, why = MAGIC_SHOP, "walk to the Magic Shop for a ring or amulet"
        elif not self.magic_done and self.wands_wanted() and len(view.stores) > MAGIC_SHOP \
                and self.gold(obs) >= WAND_GOLD + self.gear_reserve(obs):
            # After the way home (Word of Recall), before more gear.
            store, why = MAGIC_SHOP, "walk to the Magic Shop for a wand or staff"
        elif not self.weapons_done and len(view.stores) > WEAPONSMITH and self.gold(obs) > self.gear_reserve(obs):
            store, why = WEAPONSMITH, "walk to the Weaponsmith for a better weapon"
        elif not self.armoury_done and len(view.stores) > ARMOURY and self.gold(obs) > self.gear_reserve(obs):
            store, why = ARMOURY, "walk to the Armoury for better armour"
        else:
            return None
        self.at_store = store
        door = view.stores[store]
        step = view.step_toward({door}, avoid_monsters=True) or view.step_toward({door}, avoid_monsters=False)
        return self.move(view, step, "shop", why)

    def recall_trip(self, obs: Observation, view: View) -> Decision | None:
        """Word of Recall instead of the stairs (M4 round 44: reach_dl10 lost
        6 of 10 characters to starvation looking for up staircases): read one
        deep with supplies low, and in town once shopping is done to go back
        to the deepest level. Waiting for the yank, stay put: stairs would
        undo the trip."""
        if self.recalling:
            return Decision(ord("5"), "recall", "Word of Recall read: wait for it")
        if not self.recall:
            # The count says none, but counts drift: stuck, look anyway, once
            # a while (the read list corrects the counts, sync_counts). Five
            # C64 Balrog characters at level 18-26 searched sealed DL1-3
            # pockets to their budgets, four with Word of Recall in the pack
            # by its listings (2026-11-06).
            if obs.dlvl == 0 or not (self.stuck(view) or self.hopping_out()) or obs.step < self.recall_look_after:
                return None
            self.recall_look_after = obs.step + STUCK_STEPS
        if obs.dlvl == 0:
            spare = self.gold(obs) > self.gear_reserve(obs)
            # The Temple only when it was worth a visit, as the Black Market:
            # waiting on a Temple visit never made left characters with two
            # scrolls walking down from DL1 (C128 catalog cycle, 2026-11-02:
            # 82 recalls up, 11 down).
            ready = self.shopped and (self.potions_done or len(view.stores) <= TEMPLE
                                      or not self.temple_worth_it(obs)) and (
                self.magic_done or self.book_next not in MAGE_BOOKS or self.gold(obs) < BOOK_GOLD.get(self.book_next, 0)) and (
                self.alchemist_done or self.recall >= self.recall_reserve() or self.gold(obs) < RECALL_GOLD) and (
                self.market_done or not self.market_worth_it(obs)) and not self.to_wear and (
                self.weapons_done or not spare) and (self.armoury_done or not spare)
            if not ready or self.max_dlvl < RECALL_FROM or self.supplies_low() or self.recall < 2:
                # The last scroll is the way home, not the way down (M5a).
                return None
            if obs.clvl < ready_level(self.max_dlvl, self.goal.ready_margin, self.goal.ready_taper) - 1:
                # Recall goes back to the deepest level: not when that is too
                # deep to stay (resupply's too_deep), or the bot climbs, recalls
                # up and recalls down again. A level-25 Balrog graduate went
                # DL28-27-26-town-DL28 over and over (M8, 2026-11-02). The
                # stairs go down a level at a time instead.
                return None
        elif not (self.food_low() and self.sealed(view)) and not self.stuck(view) and not self.lightless() \
                and not self.hopping_out() and (
                obs.dlvl < RECALL_FROM or not self.needs_resupply(obs)) and not (
                self.draining >= DRAIN_RESTS and obs.hp < DRAIN_RECALL_HP * obs.mhp) and not (
                self.level.summoned is not None and obs.step - self.level.summoned <= SUMMON_MEMORY
                and not (view.stairs_up() | view.stairs_down())):
            # A summoner on a level with no staircase known: Word of Recall is
            # the way out (deep goal).
            # Draining away with nothing to cure it: the Temple is a recall
            # away, 15-35 turns at a point a turn (deep goal).
            # Sealed in and short of food, any depth: the only other way out
            # is a secret door the searches have not found (M4 round 53: 4
            # of 11 reach_dl10 deaths starved searching).
            return None
        if obs.step < self.blind_until:
            return None
        self.picking, self.listed = RECALL, False
        return Decision(ord("R"), "recall", "read Word of Recall")

    def still_there(self, pos: Pos, obs: Observation) -> bool:
        """The creature at ``pos`` has stood there STILL_STEPS or more."""
        since = self.level.still.get(pos)
        return since is not None and obs.step - since[1] >= STILL_STEPS

    def lightless(self) -> bool:
        """Dark with nothing to light: no torch, and no lantern with oil. The
        way up cannot be seen, at any depth (M5b round 44, seed 1003: 60
        trips between DL1 and DL2 hunting for an up staircase in the dark)."""
        return self.dark and not self.torches and not (self.lamp and self.oil)

    def stuck(self, view: View) -> bool:
        """No new map or experience for a long while (searching a sealed
        pocket, wandering a level): Word of Recall is the way out whatever
        the food (M4 rounds 78-80: ~10 of ~33 deaths a round searched or
        wandered a level until they starved)."""
        return self.level.since_progress >= STUCK_STEPS

    @staticmethod
    def gold(obs: Observation) -> int:
        """The status line's gold. "AU:739K" is 739,000: read as 739 from
        the K format's arrival (2026-11-05), rich C64 characters took no gear
        trips and bought nothing dear (2026-11-06)."""
        match = STATUS_GOLD.search(obs.rows[23])
        return int(match.group(1)) * (1000 if match.group(2) else 1) if match else 0

    def wear(self, obs: Observation, view: View) -> Decision | None:
        """Wield or wear what was bought, in town before going down; a ring or
        amulet found below as soon as nothing is close (jewel_better)."""
        if not self.to_wear:
            return None
        if obs.dlvl != 0 and not (JEWEL_NAME.match(self.to_wear[0].strip()) and not self.close_threats(obs, view)):
            return None
        self.picking, self.listed = self.to_wear.pop(0), False
        return Decision(KEY_WEAR, "wear", f"wear the {self.picking}")

    def market_worth_it(self, obs: Observation) -> bool:
        """A Black Market trip for Word of Recall with plenty of gold, or, rich,
        for its enchanted armour and weapons (``gear_pick``)."""
        gold = self.gold(obs)
        return (self.recall < self.recall_reserve() and gold >= MARKET_GOLD) or gold >= MARKET_GEAR_GOLD

    def temple_worth_it(self, obs: Observation) -> bool:
        """A Temple trip only with the gold for what is wanted there."""
        gold = self.gold(obs)
        book = self.book_wanted(obs)
        return (self.clw < self.clw_reserve() and gold >= CLW_GOLD) or \
            (self.strong_wanted() and gold >= STRONG_GOLD[CSW]) or \
            (self.recall < self.recall_reserve() and gold >= RECALL_GOLD) or \
            (book is not None and book not in MAGE_BOOKS and gold >= BOOK_GOLD.get(book, 0))

    def quaff(self, obs: Observation, view: View) -> Decision | None:
        """Badly hurt with a Cure Light Wounds potion: drink it (M4), in town
        too (M5b round 3: poison drained characters there, where the bot never
        rests).

        Not beside creatures that are all slower than the player while a
        step away exists: a potion heals ~8 while a Creeping Coins nest hits
        for ~12 a turn, and stepping away costs nothing they can catch up
        to (M5a round 10: a Half-Elf drank five in a row beside them and
        died). Out of reach, the next decision drinks.

        A known Cure Light Wounds is prayed before the potion even one blow
        from death: drinking first at low levels (the prayer can fail) cost
        Gnome and Elf Priests 5 of 40 on reach_dl8 (M5f round 7 A/B)."""
        strong = next((k for k in self.strong if self.strong[k]), None)
        if self.restoration and self.restore_due and not self.close_threats(obs, view):
            self.picking, self.listed = RESTORATION, False
            return Decision(ord("Q"), "quaff", "a stat drained: drink Restoration")
        gain = next((k for k, n in self.gains.items() if n), None)
        if gain is not None and not self.close_threats(obs, view):
            # A stat for good, as a player drinks one the moment it is known.
            self.picking, self.listed = gain, False
            return Decision(ord("Q"), "quaff", f"drink {gain[len('Potion of '):]}")
        if obs.step < self.blind_until and self.clw:
            # Cure Light Wounds cures blindness (VMS potions.inc case 13; Moria8
            # since 2026-10-31): the scroll can then be read.
            self.picking, self.listed = CLW, False
            return Decision(ord("Q"), "quaff", "blind: drink Cure Light Wounds")
        poisoned = self.poisoned or self.draining >= DRAIN_RESTS
        if self.neutralize and poisoned and obs.hp < DRAIN_RECALL_HP * obs.mhp and not self.adjacent \
                and not any(self.magic.can(obs, cure) for cure in (CURE_POISON, NEUTRALIZE_POISON, SLOW_POISON)):
            # Out of the fight with no cure to cast: a Black Mamba's bites
            # stack poison, and Gnome Mages at 1 mana drained to death after
            # it (C128, 2026-11-05). Not beside it: the next bite poisons again.
            self.picking, self.listed = NEUTRALIZE, False
            return Decision(ord("Q"), "quaff", f"HP {obs.hp}/{obs.mhp} poisoned: drink Neutralize Poison")
        if self.strong[CCW] and self.draining >= DRAIN_RESTS and obs.hp < DRAIN_RECALL_HP * obs.mhp:
            # Cure Critical Wounds also cures poison; Serious does not (VMS
            # potions.inc cases 14-15).
            strong = CCW
            self.picking, self.listed = strong, False
            return Decision(ord("Q"), "quaff", f"HP {obs.hp}/{obs.mhp} draining: drink {strong[len('Potion of '):]} Wounds")
        if not (self.clw or strong) or (obs.hp >= QUAFF_HP * obs.mhp and not (
                (self.under_spell(obs, view) or self.under_blow(obs, view)) and not self.magic.can(obs, CURE_LIGHT))):
            return None
        beside = {p for p, c in view.creatures.items() if chebyshev(p, view.pos) == 1 and not self.stationary(c)}
        if beside and all((view.creatures[p].glyph, view.creatures[p].level) in knowledge.slow_kinds() for p in beside):
            away = self.walk_away(view, beside)
            if away is not None:
                return Decision(away.key, "retreat", "hurt beside slow creatures: step away before drinking")
        # Only a potion that outruns what the creatures beside do a turn, as
        # for a prayer: a level-25 Half-Troll drank seven, Cure Serious then
        # Cure Light, beside a Swordsman and a Stone Giant that took more
        # back each turn, and died with none left (M8, 2026-11-02). Fighting
        # on, phasing or leaving does better.
        # The potion rule (maintainer, 2026-11-03): with nothing that can
        # hurt the character, rest instead; else only a potion that leaves it
        # alive after the next turn (danger under HP plus the heal) and heals
        # at least a third of the danger ("no rope-a-doping").
        danger = self.danger(view.pos, view, obs)
        if danger == 0 and not (self.poisoned or self.draining):
            return None
        order = [strong, CLW] if strong is not None and (not self.clw or obs.mhp - obs.hp > STRONG_DEFICIT) \
            else [CLW, *sorted((k for k in self.strong if self.strong[k]), key=POTION_HEAL.get)]
        potion = next((k for k in order if k is not None and (self.clw if k == CLW else self.strong.get(k))
                       and danger < obs.hp + POTION_HEAL[k] and POTION_HEAL[k] >= danger / 3), None)
        if potion is None and obs.hp < RETREAT_HP * obs.mhp and not self.can_phase(obs) \
                and any(not self.stationary(c) for c in self.adjacent):
            # The third of the danger asks for a better way out ("phasing or
            # leaving does better"): with none, a potion that still outlasts
            # the next turn beats melee. Mages at clvl 17-22 spent their mana,
            # then fought to the death holding five Cure Light Wounds (C128,
            # 2026-11-04: 23 of 25 such deaths). Not when no potion outlasts it.
            potion = next((k for k in sorted(POTION_HEAL, key=POTION_HEAL.get, reverse=True)
                           if (self.clw if k == CLW else self.strong.get(k))
                           and danger < obs.hp + POTION_HEAL[k]), None)
        if potion is None:
            return None
        self.picking, self.listed = potion, False
        return Decision(ord("Q"), "quaff", f"HP {obs.hp}/{obs.mhp}: drink {potion[len('Potion of '):]} Wounds")

    def restock_short(self) -> bool:
        """Short enough of strong potions or Phase Door for a town trip (M7)."""
        return self.strong_wanted() and (not any(self.strong.values()) or not self.phase)

    def strong_wanted(self) -> bool:
        """Fewer than ``strong_reserve`` stronger potions from STRONG_LEVEL (M7)."""
        return ("strong_potions" in self.goal.tactics and self.clvl >= STRONG_LEVEL
                and sum(self.strong.values()) < self.strong_reserve())

    def strong_reserve(self) -> int:
        """STRONG_RESERVE, more the deeper it has been: a level-34 Priest with
        245 HP met DL31 with one Cure Serious Wounds at a time (2026-11-07)."""
        return max(STRONG_RESERVE, 5 + self.max_dlvl // STRONG_PER_DLVL)

    def teleport_reserve(self) -> int:
        """TELEPORT_RESERVE once it has been TELEPORT_FROM deep, else none."""
        return TELEPORT_RESERVE if self.max_dlvl >= TELEPORT_FROM else 0

    def phase_reserve(self) -> int:
        """PHASE_RESERVE, more the deeper it has been (an escape a fight)."""
        rich = PHASE_RESERVE_RICH if self.gold_seen >= MARKET_GEAR_GOLD else 0
        return max(PHASE_RESERVE, self.max_dlvl // PHASE_PER_DLVL, rich)

    def phase_door(self, obs: Observation, view: View) -> Decision | None:
        """Badly hurt in contact with no retreat (``retreat`` came first and
        found no step out): read Phase Door. Only beside a breeder, beside
        two or more, or near death: a Paladin stood 250 steps on one square
        killing Blue Worm masses as fast as they bred, every step out into
        contact, and died there (M5b round 11). Away from them, ``retreat``
        and ``stair_scum`` take over."""
        magic = self.magic
        if not self.phase_due(obs):
            return None
        # Escaping means making for the stairs after the phase too (``retreat``
        # commits while hurt and picks the staircase): a level-4 Elf Priest
        # phased from an Orc at 5 HP, saw nothing, explored straight back to
        # it and died (C128, 2026-11-04).
        self.level.retreat_to = self.level.retreat_to or view.pos
        beside = [c for c in self.adjacent if not self.stationary(c)]
        if len(beside) >= 2 and magic.can(obs, SANCTUARY):
            # Sleeps every adjacent creature: the retreat then walks off.
            return Decision(*magic.pray(SANCTUARY, f"HP {obs.hp}/{obs.mhp}, {len(beside)} beside: pray Sanctuary"))
        other_way = self.phase or magic.can(obs, PORTAL) or magic.can(obs, PHASE_DOOR) or magic.can(obs, TELEPORT_SELF)
        grave = (obs.hp < QUAFF_HP * obs.mhp or obs.step < self.heals_losing_until
                 or any(self.dangerous(c, obs) for c in beside))
        far = self.far_escape(obs, f"HP {obs.hp}/{obs.mhp}, no way out") if grave or not other_way else None
        if far is not None:
            # Far, not a few squares: a fast creature caught every Phase Door.
            return far
        close = [p for p, c in view.creatures.items() if chebyshev(p, view.pos) == 1 and not self.stationary(c)]
        if self.wands.get(TELEPORT_AWAY, 0) > 0 and len(close) == 1 and (grave or not other_way):
            step = (close[0][0] - view.pos[0], close[0][1] - view.pos[1])
            self.picking, self.listed, self.pending, self.last_aimed = TELEPORT_AWAY, False, DIRS[step], TELEPORT_AWAY
            return Decision(KEY_AIM, "phase", f"HP {obs.hp}/{obs.mhp}, no way out: aim the {TELEPORT_AWAY} at "
                                              f"'{view.creatures[close[0]].glyph}'")
        if (self.level.phased is not None and obs.step - self.level.phased <= PHASE_AGAIN
                and magic.can(obs, TELEPORT_SELF)):
            # A Phase Door that lands back in contact is no escape: a level-21
            # Mage cast it 30 times in a Vorpal Bunny swarm on DL17, each jump
            # among more of them, and died with Teleport Self known (C128,
            # 2026-11-05). Far, then the stairs.
            return Decision(*magic.pray(TELEPORT_SELF, f"HP {obs.hp}/{obs.mhp}, caught again: cast Teleport Self"))
        if self.phase:
            if obs.step < self.blind_until:
                return None
            self.picking, self.listed = PHASE, False
            self.level.phased = obs.step
            return Decision(ord("R"), "phase", f"HP {obs.hp}/{obs.mhp}, no way out: read Phase Door")
        if magic.can(obs, PORTAL):
            return Decision(*magic.pray(PORTAL, f"HP {obs.hp}/{obs.mhp}, no way out: pray Portal"))
        if magic.can(obs, PHASE_DOOR):
            # The scroll first: the spell can fail (a Ranger's 35%, a Rogue's 55%).
            self.level.phased = obs.step
            return Decision(*magic.pray(PHASE_DOOR, f"HP {obs.hp}/{obs.mhp}, no way out: cast Phase Door"))
        if magic.can(obs, TELEPORT_SELF):
            return Decision(*magic.pray(TELEPORT_SELF, f"HP {obs.hp}/{obs.mhp}, no way out: cast Teleport Self"))
        return None   # Sanctuary known, one beside: nothing that helps (M5b round 24: Portal asked 1,666 times)

    def swarm_recall(self, obs: Observation, view: View) -> Decision | None:
        """A swarm of fast breeders: read Word of Recall at once and fight on
        while it comes. Too fast to walk away from and breeding faster than
        they die, Huge White Bats, Giant Fleas, Lice and Gnats killed 51
        characters on 2026-11-06, nearly all with Word of Recall and potions
        unused (levels 19-30 on the Balrog queue)."""
        if obs.dlvl == 0:
            return None
        breeders, moves = knowledge.breeder_kinds(), knowledge.moves()
        swarm = sum((c.glyph, c.level) in breeders and moves.get((c.glyph, c.level), 1.0) > 1
                    and not self.stationary(c) for c in view.creatures.values())
        if swarm < SWARM_RECALL:
            return None
        if self.recall and not self.recalling and obs.step >= self.blind_until:
            self.picking, self.listed = RECALL, False
            return Decision(ord("R"), "recall", f"{swarm} breeders in view: read Word of Recall")
        # No Recall (or waiting for it): fight through to a staircase, any
        # way. A level-25 Dwarf with none stood on one DL4 square 700 steps
        # among 18 Giant White Lice, drank 23 strong potions and 9 Cure Light
        # Wounds, and died there (C64 Balrog, 2026-11-06).
        here = view.type_at(*view.pos)
        if here in (TYPE_STAIRS_UP, TYPE_STAIRS_DN):
            return Decision(ord("<") if here == TYPE_STAIRS_UP else ord(">"), "retreat",
                            f"{swarm} breeders in view: take the stairs")
        step = view.step_toward(view.stairs_up() | view.stairs_down(), avoid_monsters=False)
        if step is None or step == (0, 0):
            return None
        return Decision(DIRS[step], "retreat", f"{swarm} breeders in view: fight through to the stairs")

    def phase_due(self, obs: Observation) -> bool:
        """``phase_door`` will act now: an escape at hand, and badly hurt in
        contact beside a breeder, two or more, or near death, or beside an
        outmatched creature at any HP. An outmatched creature in contact (a
        naga: too strong by the lore, no faster than a walk) is left before
        the fight: four Human Priests met DL5 Green Nagas at full HP, every
        step to the stairs past them, and fought them to the end (M5b round
        53)."""
        beside = [c for c in self.adjacent if not self.stationary(c)]
        # Deep goal: just after a summoning or a ghost's strike, anything in
        # contact is escaped at once: characters at clvl 23 on DL26 went from
        # 146 HP to dead in three turns beside a Quylthulg's Banshee (M7
        # queue, 2026-10-31), the stairs and Word of Recall too slow.
        summoned = ("summon_phase" in self.goal.tactics and self.level.summoned is not None
                    and obs.step - self.level.summoned <= SUMMON_MEMORY)
        outmatched = summoned or any(self.dangerous(c, obs) for c in beside) or obs.step < self.heals_losing_until
        # Hit by what cannot be seen (blind, or invisible) while the heals
        # lose: the escape too, with nothing beside in view.
        unseen = not beside and self.attacked and obs.step < self.heals_losing_until
        if unseen and obs.dlvl and self.can_phase(obs):
            return True
        if obs.dlvl == 0 or not beside or (obs.hp >= RETREAT_HP * obs.mhp and not outmatched) or not (
                self.can_phase(obs) or self.magic.can(obs, SANCTUARY)):
            return False
        breeders = knowledge.breeder_kinds()
        return (len(beside) >= 2 or any((c.glyph, c.level) in breeders for c in beside)
                or obs.hp < QUAFF_HP * obs.mhp or outmatched)

    def far_escape(self, obs: Observation, why: str) -> Decision | None:
        """A long jump across the level, not a few squares: the Staff of
        Teleportation while it has charges, else a Scroll of Teleportation.
        None while blind (neither can be used) or with neither held."""
        if obs.step < self.blind_until:
            return None
        if self.wands.get(TELEPORT_STAFF, 0) > 0:
            self.picking, self.listed, self.last_aimed = TELEPORT_STAFF, False, TELEPORT_STAFF
            return Decision(KEY_USE, "phase", f"{why}: use the {TELEPORT_STAFF}")
        if self.teleports:
            self.picking, self.listed = TELEPORT_SCROLL, False
            return Decision(ord("R"), "phase", f"{why}: read {TELEPORT_SCROLL}")
        return None

    def can_phase(self, obs: Observation) -> bool:
        """A Phase Door or Teleportation scroll held, or Portal, Phase Door or Teleport Self castable now."""
        magic = self.magic
        return bool(self.phase) or bool(self.teleports) or magic.can(obs, PORTAL) or magic.can(obs, PHASE_DOOR) or magic.can(obs, TELEPORT_SELF) \
            or self.wands.get(TELEPORT_STAFF, 0) > 0 or self.wands.get(TELEPORT_AWAY, 0) > 0

    def drop_junk(self, obs: Observation, view: View) -> Decision | None:
        """A full pack refused every purchase: worn-out armour and weapons
        replaced by better ones, and burnt-out torches, stayed in it, and two
        Dwarf Priests hopped between town and DL 1 for 4,000 steps unable to
        buy food (M5b round 29). Drop one thing the bot has no use for,
        with nothing in view."""
        threats = self.threats(view)
        if obs.dlvl == 0:
            # Townspeople are nearly always in view: only one close stops it,
            # or nothing was ever dropped in town and every visit's purchases
            # were refused (2026-11-06: 70 and 170 Word of Recall refusals).
            threats = {p for p in threats if chebyshev(p, view.pos) <= 2}
        if not (self.pack_full or self.more_junk) or obs.step < self.drop_after or threats:
            return None
        self.dropping, self.listed = True, False
        return Decision(KEY_DROP, "drop", "pack full: drop what is not needed")

    def drop_prompt(self, obs: Observation) -> Decision:
        """The drop prompt: list the pack, then drop the first item not kept."""
        if obs.stage != "list":
            if not self.listed:
                self.listed = True
                return Decision(ord("?"), "prompt", "list the pack")
        else:
            self.sync_counts(obs.rows[1:], "all")   # the whole pack: every count it can check
            # The launcher carried and its ammunition only: a level-25 Dwarf
            # kept three launchers, seven stacks of arrows and bolts, three
            # empty lanterns and three burnt-out torches, dropped one item a
            # town trip, and every purchase of light and Word of Recall
            # failed on the full pack (M8, 2026-11-02).
            missiles = ((self.launcher, LAUNCHERS[self.launcher][0]) if self.launcher is not None
                        else (*LAUNCHERS, *AMMO_AVERAGE))
            # The melee weapon is in the pack while the launcher is wielded.
            # Only the wands and staffs it uses: every "Wand of" kept filled a
            # level-16 Mage's pack until the General Store refused its food
            # and light, and it starved in the dark (C128, 2026-11-05).
            recharging = any(n in self.magic.known and not self.magic.confirmed(n) for n in RECHARGE_SPELLS)
            useful = (*ATTACK_WANDS, TELEPORT_STAFF, TELEPORT_AWAY, *(RECHARGEABLE if recharging else ()))
            keep = KEEP_PREFIXES + missiles + ((self.weapon[0],) if self.wielding_launcher else ()) + tuple(useful)

            matches = [PACK_ITEM.match(row) for row in obs.rows[1:]]
            # One of each wand or staff, the most charged: they do not stack,
            # and an Elf Rogue's four Wands of Lightning and four of Teleport
            # Away filled its pack (2026-11-05). The rest are spare.
            best: dict[str, tuple[int, int]] = {}
            for i, m in enumerate(matches):
                if m and m.group(2).startswith(("Wand of", "Staff of")):
                    charges = CHARGES.search(m.group(2))
                    key = (int(charges.group(1)) if charges else 0, -i)
                    base = m.group(2).split(" (")[0].strip()
                    best[base] = max(best.get(base, key), key)
            extra = {i for i, m in enumerate(matches) if m and m.group(2).startswith(("Wand of", "Staff of"))
                     and best[m.group(2).split(" (")[0].strip()][1] != -i}
            # The three strongest attack wands (2026-11-05: six kinds and five
            # part-burnt torches, one slot each, filled 22-slot packs).
            kinds = sorted({m.group(2).split(" (")[0].strip() for i, m in enumerate(matches)
                            if m and i not in extra and m.group(2).split(" (")[0].strip() in ATTACK_WANDS},
                           key=ATTACK_WANDS.get, reverse=True)
            extra |= {i for i, m in enumerate(matches) if m and m.group(2).split(" (")[0].strip() in kinds[KEEP_ATTACK_WANDS:]}
            # The fullest spare torches only: one beside a lantern worn, else the reserve.
            torches = sorted(((int(t.group(1)), i) for i, m in enumerate(matches)
                              if m and m.group(2).startswith(TORCH) and (t := LIGHT_TURNS.search(m.group(2)))),
                             reverse=True)
            extra |= {i for _, i in torches[(1 if self.lamp else TORCH_RESERVE):]}

            def junk(match: re.Match[str] | None) -> bool:
                if match is not None and matches.index(match) in extra:
                    return True
                name = match.group(2) if match else ""
                # A burnt-out torch or lantern, and an empty wand or staff: kept,
                # empty wands filled a Warrior's pack one slot each until the
                # stores refused even its food (2026-11-05: 1,254 refusals).
                spent = "(0 turns)" in name or "(0 charges)" in name
                return match is not None and (spent or not (name.startswith(keep) or self.unknown_kept(name))) \
                    and name not in self.to_wear
            for match in matches:
                if junk(match):
                    assert match is not None
                    self.more_junk = sum(map(junk, matches)) > 1   # drop the rest next, one a step
                    self.dropping = self.pack_full = False
                    if obs.dlvl == 0:
                        # Room made in town: back to the General Store, whose
                        # refused ration ended the visit (M5b round 47, seed
                        # 1014: a level-9 Dwarf starved walking between shops),
                        # and to the store that refused for a full pack.
                        self.shopped = False
                        self.reopen_refused()
                    return Decision(ord(match.group(1).upper()), "prompt", f"drop {match.group(2).strip()}")
            # Nothing else spare: an unknown flavour goes before the food and
            # light a refused purchase was for (2026-11-05: a level-15 Mage with
            # 5,136 gold and a full pack had every purchase refused, 150,000
            # steps between town and DL2).
            spare = next((m for m in matches if m is not None and unknown_kind(m.group(2))), None)
            if spare is not None:
                self.unknown[re.sub(r"^an? ", "", spare.group(2).strip())] = 0
                self.dropping = self.pack_full = False
                self.shopped = self.shopped and obs.dlvl != 0
                if obs.dlvl == 0:
                    self.reopen_refused()
                return Decision(ord(spare.group(1).upper()), "prompt", f"drop {spare.group(2).strip()}: nothing else to spare")
        self.dropping = self.pack_full = self.more_junk = False
        self.drop_after = obs.step + DROP_RETRY   # nothing to spare: not again for a while
        # What the full pack held, for the trace: a full pack refused food and
        # light in many games (2026-11-05), and only the listing tells why.
        held = "; ".join(m.group(2).strip()[:24] for m in (PACK_ITEM.match(r) for r in obs.rows[1:]) if m)
        return Decision(KEY_RUNSTOP, "prompt", f"nothing to drop: cancel ({held})" if held else "nothing to drop: cancel")

    @staticmethod
    def searching(obs: Observation) -> bool:
        """Search mode on: the status line shows "Search*" (row 21 or 23 by layout)."""
        return any("Search*" in row for row in obs.rows[21:24])

    def search_hazard(self, obs: Observation) -> str | None:
        """Why search mode's half speed could kill now, or None."""
        if self.unseen_attack or self.level.retreat_to is not None:
            return "under attack"
        if obs.hp < HUNT_HP * obs.mhp:
            return "hurt"
        return None

    def search_mode(self, obs: Observation, view: View) -> Decision | None:
        """Search mode while moving about with nothing in view: every step
        searches the squares around, finding traps before they spring
        (maintainer, 2026-10-25: rockfall traps killed level-1 Priests). It
        halves speed (an extra turn after each action); the game turns it off
        when a creature comes into view, on any attack or trap, and on a new
        level, as Umoria's playerDisturb does.

        Not always, though: a spell does not disturb (VMS), and a creature out
        of the light never came into view. So the bot turns it off itself
        when hurt or under attack, and does not turn it back on then. M6:
        a C128 Warrior fled a Novice Priest's spells at half speed for 30
        steps; Apple IIe Mages died resting from poison, searching."""
        hazard = self.search_hazard(obs)
        if self.searching(obs):
            if hazard and obs.dlvl:
                return Decision(KEY_SEARCH_MODE, "search-mode", f"{hazard}: search mode off")
            return None
        if self.food_low():
            # Not on the way home for food: each step would cost two turns of
            # it, and on the 80-column ports' 198x66 maps warriors starved
            # walking home searching (M6).
            return None
        if hazard or obs.dlvl == 0 or self.threats(view) or obs.step < self.search_mode_after:
            return None
        self.search_mode_after = obs.step + SEARCH_MODE_EVERY
        return Decision(KEY_SEARCH_MODE, "search-mode", "nothing in view: search mode on")

    def invoke(self, obs: Observation, view: View, *, cornered: bool = False) -> Decision | None:
        """A caster's fighting prayers, each only with mana left for the best
        heal (``Magic.spare``): Orb of Draining (3d6 + level, doubled on evil),
        or a Mage-book caster's Magic Missile (2d6, M5d), at a creature worth it
        in line within ``ORB_RANGE``, adjacent too;
        Blind Creature on a creature the character would lose to, close; Chant
        before such a fight. A Priest's spells are its strength past level 5,
        not its Flail (maintainer, 2026-10-25)."""
        magic = self.magic
        if obs.dlvl == 0 or not magic.caster(obs):
            return None
        # No spell at a breeder while something else threatens: a level-19
        # Mage cast its Lightning Bolts at a Red Worm mass while a Priest out
        # of line killed it with spells (2026-11-05).
        breeders = knowledge.breeder_kinds()
        close = sorted((p for p in self.threats(view) if not self.stationary(view.creatures[p])),
                       key=lambda p: chebyshev(p, view.pos))
        if any((view.creatures[p].glyph, view.creatures[p].level) not in breeders for p in close):
            close = [p for p in close if (view.creatures[p].glyph, view.creatures[p].level) not in breeders]
        for pos in close:
            creature = view.creatures[pos]
            step = self.line_to(view, pos, missile=True)
            if step is None or chebyshev(pos, view.pos) > ORB_RANGE:
                continue
            worth = knowledge.strength().get((creature.glyph, creature.level), (0.0, 0))[0] >= OIL_WORTH_HP
            trial = self.trial_at(obs, creature, pos)
            if trial is not None:
                self.pending = DIRS[step]
                self.aimed = (pos, creature.glyph)
                return Decision(*magic.pray(trial, f"try {trial} at '{creature.glyph}': its effect not seen yet"))
            if magic.spare(obs, ORB) and worth:
                self.pending = DIRS[step]
                self.aimed = (pos, creature.glyph)
                return Decision(*magic.pray(ORB, f"pray Orb of Draining at '{creature.glyph}'"))
            attack = self.mage_attack(obs, creature)
            if attack is not None and not cornered and (creature.glyph, creature.level) in breeders:
                # Half the mana stays for Phase Door or Teleport Self: Mages
                # spent theirs bolt by bolt on Huge White Bats and Vorpal
                # Bunnies as they bred, then met the swarm with 1 mana (C128,
                # 2026-11-05: about half the deaths from clvl 17).
                mana, top = magic.mana(obs)
                if mana - magic.known[attack].mana < BREEDER_MANA * top:
                    attack = None
            if attack is not None and worth and (cornered or not self.phase_due(obs)):
                # 2d6, a flask's damage, for 1 mana (M5d). Hurt with a
                # creature beside, the escapes come first: four Rangers cast
                # it at 1-9 HP beside DL1 Kobolds, a third of the casts
                # failing, and died holding Phase Door (M5d round 4). Only
                # when ``phase_door`` will act: otherwise the cast beats the
                # oil or dagger that came next. Level-1 Halfling Mages at 1-4
                # HP threw oil at the Kobold beside them (M5f baseline: 9 of
                # 15 deaths), and once Mages learned Phase Door at level 1 they
                # threw it at full mana (round 12). ``cornered_cast`` casts
                # it once no escape was taken.
                self.pending = DIRS[step]
                self.aimed = (pos, creature.glyph)
                return Decision(*magic.pray(attack, f"cast {attack} at '{creature.glyph}'"))
            if chebyshev(pos, view.pos) <= 2 and obs.step >= self.level.blind_until \
                    and self.fight_odds(creature, obs) > FIGHT_ODDS and magic.spare(obs, BLIND):
                self.level.blind_until = obs.step + BLIND_TURNS
                self.pending = DIRS[step]
                return Decision(*magic.pray(BLIND, f"pray Blind Creature at '{creature.glyph}'"))
        blessing = CHANT if magic.spare(obs, CHANT) else BLESS if magic.spare(obs, BLESS) else None
        if obs.hp < RETREAT_HP * obs.mhp or self.level.retreat_to is not None:
            # A blessing is for a fight about to start, not a turn spent at
            # death's door: a Dwarf Priest prayed Bless at 3 of 35 HP beside
            # a Novice Mage, and died there (M5 regression, seed 1016). Nor
            # for a flight: the most common thing that stopped a run for the
            # stairs was a Priest turning to pray Bless (2026-11-03 traces).
            blessing = None
        if obs.step >= self.chant_until and blessing is not None and any(
                chebyshev(p, view.pos) <= 3 and self.fight_odds(view.creatures[p], obs) > CHANT_ODDS
                for p in close):
            # Bless before Chant is known: +2 AC and +5 to hit from level 1,
            # never prayed until M5f (Priests prayed Chant from level 7 only).
            self.chant_until = obs.step + (CHANT_TURNS if blessing == CHANT else BLESS_TURNS)
            return Decision(*magic.pray(blessing, f"a hard fight coming: pray {blessing}"))
        return None

    def pray(self, obs: Observation, view: View) -> Decision | None:
        """Priests and Paladins (M5b): learn new prayers after each level,
        read the prayer list once, then pray Remove Fear when afraid, a heal
        when hurt (potions stay for the worst moments: ``quaff`` comes
        first), Detect Doors/Stairs when the way out is lost, and Create Food
        when out of food."""
        magic = self.magic
        if not magic.caster(obs):
            return None
        near = any(chebyshev(p, view.pos) <= 2 for p in self.threats(view))
        if not near and magic.study_due:
            return Decision(*magic.study())
        if not near and not magic.listed:
            return Decision(*magic.read_list())
        if self.afraid and magic.can(obs, REMOVE_FEAR) and not self.grave(obs, view):
            # Not when the next turn may take half the HP: the escape comes
            # first. A level-34 Half-Troll Priest prayed it twice at 9/245
            # HP among a Vampire, a Frost Giant, a Black Orc and a dragon,
            # and died; 3 of its 14 deaths came mid-prayer (2026-11-07).
            return Decision(*magic.pray(REMOVE_FEAR, "afraid: pray Remove Fear"))
        cure = next((name for name in (CURE_POISON, NEUTRALIZE_POISON, SLOW_POISON) if magic.can(obs, name)), None)
        if "heal_first" in self.goal.tactics and self.adjacent and obs.hp < PRAY_HEAL_HP * obs.mhp:
            # Poison drains a point a turn; the creature beside does more: a
            # Gnome Priest prayed Neutralize Poison twice beside a Black Mamba
            # from 29 HP and died (M7 queue, 2026-10-31). Heal first.
            cure = None
        if self.poisoned and cure is not None:
            # Poison drains a 6-12 HP Mage or Priest a point a turn for 11-20
            # turns: a gas trap killed them resting (M5f).
            # Cast, it counts as cured: poison that ends or is cured without a
            # "You feel better." left a level-13 Mage casting Cure Poison
            # 14,728 times at full HP (C128, 2026-11-04). Still poisoned, the
            # HP lost each step marks it again (``note_drain``).
            self.poisoned, self.draining = False, 0
            return Decision(*magic.pray(cure, f"poisoned: pray {cure}"))
        # Sealed in or stuck, not merely "no up stairs seen yet": prayed on
        # arrival, the one try was spent before the level was explored, and
        # a Priest later sealed in there starved for 54,000 steps (M5b round
        # 7). Again every DETECT_EVERY steps. Before healing when nothing is
        # close: starving in a sealed pocket kept HP under half, so the heal
        # always came first and the way out was never looked for (M5b round
        # 8: a Paladin, 34,000 steps on one DL2 level).
        # Lightless, at once: nothing explored shows the way up (2026-11-06:
        # a level-19 Paladin with no light hopped DL3-DL4 150,000 steps, the
        # prayer known).
        lost = self.lightless() and not view.stairs_up()
        if obs.dlvl and not near and (self.stuck(view) or self.sealed(view) or lost) \
                and obs.step >= self.level.detect_after and magic.can(obs, DETECT_DOORS):
            self.level.detect_after = obs.step + DETECT_EVERY
            return Decision(*magic.pray(DETECT_DOORS, "no way out known: pray Detect Doors/Stairs"))
        # Lightless with a light spell: light what is around every few squares
        # walked, as a player does to find the way up. A level-28 Rogue with
        # Light Area known groped and searched one dark DL1 168,000 steps
        # (C64 Balrog, 2026-11-07).
        spell = next((name for name in LIGHT_SPELLS if magic.can(obs, name)), None)
        if obs.dlvl and not near and self.lightless() and spell is not None and (
                self.level.lit_at is None or chebyshev(self.level.lit_at, view.pos) >= LIT_EVERY):
            self.level.lit_at = view.pos
            return Decision(*magic.pray(spell, f"no light: {spell}"))
        hungry = any(word in obs.rows[23] for word in ("Hungry", "Weak", "Faint"))
        if obs.dlvl and not near and self.food_low() and (hungry or not self.pack_full) \
                and magic.can(obs, CREATE_FOOD):
            # Before a heal: starving drains HP back as fast as Cure Light
            # Wounds restores it, and a Dwarf Priest sealed on DL2 healed
            # 1,166 times while it starved (M5b round 29, seed 1001).
            # A full pack leaves the ration on the floor: not again until
            # hungry, or a level-18 Ranger prayed every time its mana came
            # back, 2.8 million steps on DL1 (C64 Balrog queue, 2026-11-06).
            return Decision(*magic.pray(CREATE_FOOD, "food low: pray Create Food"))
        if (obs.hp < PRAY_HEAL_HP * obs.mhp or self.under_spell(obs, view) or self.under_blow(obs, view)) \
                and not ((self.adjacent or self.attacked) and self.phase_due(obs)):
            # An escape due comes first (``phase_door``): a level-21 Mage beside
            # a Fire Spirit, a Human Zombie and a Magic User prayed Cure Light
            # Wounds five times from 35 HP to death with 25 mana and Phase
            # Door known (C128, 2026-11-04).
            # Town too: the bot never rests there, and poison kept draining
            # four Priests to death on the walk to the stores (M5b round 3).
            # Only a heal that outruns what the adjacent creatures do back:
            # Cure Light Wounds (3d3) prayed again and again beside a Kobold
            # that took more each turn, until the character died praying
            # (M5b round 8: Priest 1012, Paladin 1006 against a Novice
            # Priest). Fighting on at least hurts the creature.
            hitting = sum(self.incoming(c, obs) for c in self.adjacent)
            # What happened beats the estimate: no better off than at the last
            # heal a few steps back, the heals are losing. Mages prayed Cure
            # Light Wounds eight times in a row beside one Fire Spirit and
            # died holding five potions (C128, 2026-11-04). Escape instead.
            # Hit counts as contact with nothing seen beside: a blinded
            # level-24 Mage prayed it 13 times among a Magic User's summons,
            # HP 36-48 throughout, until its 37 mana were gone (C128,
            # 2026-11-05).
            last_hp, last_step = self.last_heal
            if (self.adjacent or self.attacked) and last_step is not None and obs.step - last_step <= HEAL_WINDOW \
                    and obs.hp <= last_hp:
                self.heals_losing_until = obs.step + HEALS_LOSING_STEPS
                return None
            for heal in HEALS:
                if magic.can(obs, heal) and (MAGE_HEAL_AVERAGE if magic.mage else HEAL_AVERAGE)[heal] > hitting:
                    self.last_heal = (obs.hp, obs.step)
                    return Decision(*magic.pray(heal, f"HP {obs.hp}/{obs.mhp}: pray {heal}"))
        return None

    def trial_at(self, obs: Observation, creature: Creature, pos: Pos) -> str | None:
        """M7 criterion 2 (§23.2): an aimed spell, or one that works on the
        creatures around, whose effect this character has not seen, tried on
        a creature it would fight anyway, while healthy. Sleep II works only
        on creatures beside the caster."""
        if not self.goal.exercise or obs.hp < EXERCISE_HP * obs.mhp or self.fight_odds(creature, obs) > FIGHT_ODDS:
            return None
        near = chebyshev(pos, obs.pos) == 1
        names = [n for n in self.magic.unconfirmed(obs, self.magic.known)
                 if (n in AIMED and n != "Turn Stone to Mud") or (n in AT_CREATURES and (near or n != "Sleep II"))]
        return names[0] if names else None

    def exercise(self, obs: Observation, view: View) -> Decision | None:
        """M7 criterion 2 (§23.2): a spell or prayer whose effect this
        character has not seen yet, cast when things are quiet: in the
        dungeon, nothing in view, HP full and most of the mana there. Turn
        Stone to Mud at a wall beside it; Identify and Recharge on the
        first pack item. Aimed spells are tried at a creature in ``invoke``."""
        magic = self.magic
        if not self.goal.exercise or obs.dlvl == 0 or not magic.caster(obs) or not magic.listed:
            return None
        mana, top = magic.mana(obs)
        if view.creatures or obs.hp < obs.mhp or mana < EXERCISE_MANA * top or obs.step < self.level.exercise_after:
            return None
        # The least cast first, the cheapest among equals: Cure Light Wounds
        # at full HP shows nothing, and a level-25 Paladin tried it 308 times
        # and never Earthquake or Sense Surroundings (C128, 2026-11-05).
        for name in sorted(magic.unconfirmed(obs, magic.known),
                           key=lambda n: int(magic.ledger.get(n, {}).get("cast", 0))):
            if name in AT_CREATURES or (name in AIMED and name != "Turn Stone to Mud"):
                continue
            if name in (CURE_POISON, NEUTRALIZE_POISON, SLOW_POISON) and not self.poisoned:
                continue   # shows nothing unpoisoned: a Gnome Mage tried Cure Poison 96 times (2026-11-05)
            if name == "Turn Stone to Mud":
                wall = next((d for d in DIRS if view.type_at(view.pos[0] + d[0], view.pos[1] + d[1]) == WALL), None)
                if wall is None:
                    continue
                self.pending = DIRS[wall]
            if name in ON_ITEM:
                if obs.step < self.on_item_after.get(name, 0):
                    continue
                self.pending_item = ord("A")
            self.level.exercise_after = obs.step + EXERCISE_EVERY
            return Decision(*magic.pray(name, f"try {name}: its effect not seen yet"))
        return None

    def find_traps(self, obs: Observation, view: View) -> Decision | None:
        """A Mage's Find Hidden Traps/Doors or a Priest's Find Traps on each new level and every
        ``FIND_TRAPS_EVERY`` steps after, with nothing in view: it shows the
        traps of the screen around the character, and a found trap is
        disarmed or walked around, not stepped on. Falling rock, pits and
        poison gas killed one 6-9 HP Mage in five (M5f baseline)."""
        spell = next((name for name in (FIND_TRAPS, PRIEST_FIND_TRAPS) if self.magic.spare(obs, name)), None)
        if obs.dlvl == 0 or self.threats(view) or obs.step < self.level.find_traps_after or spell is None:
            return None
        self.level.find_traps_after = obs.step + FIND_TRAPS_EVERY
        return Decision(*self.magic.pray(spell, f"pray {spell}"))

    def mage_attack(self, obs: Observation, creature: Creature) -> str | None:
        """The Mage-book attack that kills ``creature`` (its lore HP) in the
        fewest casts, the cheapest of those: Magic Missile while one or two
        do, Lightning or Frost Bolt for a bigger creature (M5f: Mages learned
        Stinking Cloud and the bolts but cast only Magic Missile)."""
        hp = knowledge.strength().get((creature.glyph, creature.level), (0.0, 0))[0] or 1.0
        usable = [name for name in MAGE_ATTACKS if self.magic.spare(obs, name)]
        if not usable:
            return None
        return min(usable, key=lambda name: (math.ceil(hp / MAGE_ATTACKS[name]), self.magic.known[name].mana))

    def leave_caster(self, obs: Observation, view: View) -> Decision | None:
        """A caster seen or heard on this level lately whose biggest spell
        (the lore's ``spell_burst``), cast ``CASTER_BURSTS`` times, could
        kill at the character's HP: take the stairs to a fresh level rather
        than explore within its reach. A Novice Mage's Cause Light Wounds
        does 3d8, and one blinked out of the light then hit a Gnome Priest
        from 24 HP to 8 and killed it with the next (M5f round 6: caster
        spells the largest cluster of Priest deaths); an unseen Novice Priest
        frightened another at full HP (29), then cast 14 and 17 four turns
        apart (round 8, seed 1008). ``fight`` comes first: one in contact is
        fought."""
        if obs.dlvl == 0:
            return None
        burst = max((knowledge.spell_burst().get(kind, 0) for kind, seen in self.level.casters.items()
                     if obs.step - seen <= CASTER_MEMORY), default=0)
        if "group_casters" in self.goal.tactics:
            # Every caster in view casts: a pack of Orc Shamans took a 56-HP
            # level-13 Elf Mage from 24 to dead in two turns while each
            # alone looked harmless (M7 queue, 2026-10-31).
            burst = max(burst, sum(knowledge.spell_burst().get((c.glyph, c.level), 0)
                                   for c in view.creatures.values()))
        if not burst or obs.hp > CASTER_BURSTS * burst:
            return None
        why = f"a caster's spell ({burst}) could kill at HP {obs.hp}"
        here = view.type_at(*view.pos)
        deeper_ok = self.deeper_ok(obs)
        if here == TYPE_STAIRS_UP or (here == TYPE_STAIRS_DN and deeper_ok):
            return Decision(ord("<") if here == TYPE_STAIRS_UP else ord(">"), "leave-caster",
                            f"{why}: take the stairs")
        exits = view.stairs_up() | (view.stairs_down() if deeper_ok else set())
        if not exits:
            return None
        far = view.path_steps(exits, avoid_monsters=True)
        if not view.creatures and (far is None or far > LEAVE_WALK_STEPS):
            # Not a long walk hurt in its reach: heal at once, then Word of
            # Recall first. A level-37 Priest walked 25 steps toward stairs at
            # 115-151/292 with an Ancient Blue Dragon (240) about, its hundred
            # Cure Serious unused, and was breathed on (C64 Balrog, 2026-11-08).
            heal = self.heal_now(obs, f"{why}, far from the stairs")
            if heal is not None:
                return heal
            if not self.recalling and self.recall and obs.step >= self.blind_until:
                self.picking, self.listed = RECALL, False
                return Decision(ord("R"), "recall", f"{why}: read Word of Recall")
        if any(knowledge.casts(c.glyph, c.level) for c in view.creatures.values()):
            # One in view gets free shots at a long walk: stand and fight it
            # instead, as ``retreat`` does (M4 round 28).
            far = view.path_steps(exits, avoid_monsters=True, doors=False)
            if far is None or far > RETREAT_RANGE:
                return None
        return self.move(view, view.step_toward(exits, avoid_monsters=True), "leave-caster",
                         f"{why}: path to the nearest staircase")

    def cornered_cast(self, obs: Observation, view: View) -> Decision | None:
        """Hurt beside a creature, with no escape taken (no Phase Door yet,
        no potion, nowhere to run): Magic Missile rather than the melee
        ``fight`` would choose. A level-1 Elf Mage at 2 of 8 HP beside a hurt
        Kobold swung its dagger with the mana for a missile, and died (M5f
        baseline, seed 1009)."""
        return self.invoke(obs, view, cornered=True)

    def descend(self, obs: Observation, view: View) -> Decision | None:
        if not self.deeper_ok(obs):
            return None
        if view.type_at(*view.pos) == TYPE_STAIRS_DN:
            return Decision(ord(">"), "descend", "on a down staircase")
        stairs = view.stairs_down()
        if not stairs:
            return None
        step = view.step_toward(stairs, avoid_monsters=True)
        if step is None and not any((c.glyph, c.level) in knowledge.breeder_kinds() for c in view.creatures.values()):
            # Through creatures, but never into a breeding nest: each worm
            # killed on the way was replaced, and the swarm killed the
            # character short of the stairs (M5b round 9: 8 deaths).
            step = view.step_toward(stairs, avoid_monsters=False)
        return self.move(view, step, "descend", "path to known down staircase")

    def hunt(self, obs: Observation, view: View) -> Decision | None:
        if obs.dlvl == 0 or self.afraid or not (self.goal.want_xp or self.underleveled(obs) or self.standing):
            return None
        if self.goal.klass == "mage" and obs.clvl < MAGE_MELEE_LEVEL:
            return None   # a Mage walks to melee nothing before clvl 35
        targets = {p for p, c in view.creatures.items() if self.engageable(c, obs)}
        if not targets or (obs.hp < HUNT_HP * obs.mhp and not self.standing) or self.under_spell(obs, view):
            self.waited = 0
            return None
        nearest = min(chebyshev(p, view.pos) for p in targets)
        if nearest == 2 and self.waited < FIRST_STRIKE_WAITS:
            self.waited += 1
            return Decision(KEY_REST, "hunt", "wait for it to step into contact: first strike")
        self.waited = 0
        return self.move(view, view.step_toward(targets, avoid_monsters=True), "hunt",
                         "approach a creature worth fighting")

    def explorable(self, view: View) -> bool:
        """An unexplored edge ``explore`` would walk to: the same test, or
        resupply's walk to the down stairs and explore's walk back took turns
        (2026-11-06: 300 entries of one DL3 square, an edge reachable only
        across a known trap)."""
        frontier = view.frontier() - self.level.dead_frontier
        return (bool(frontier) and view.step_toward(frontier, avoid_monsters=True) is not None) or \
            view.step_toward(view.frontier(traps=True) - self.level.dead_frontier, avoid_monsters=True) is not None

    def explore(self, obs: Observation, view: View) -> Decision | None:
        """Walk to the nearest unexplored edge. A level marked for leaving
        (``scum``) is explored only while no usable staircase is reachable:
        there is nothing else to do there (§14.3 round 8)."""
        if obs.dlvl == 0:
            return None
        if self.level.scum:
            exits = view.stairs_up() | (view.stairs_down() if self.deeper_ok(obs) else set())
            if view.step_toward(exits, avoid_monsters=False) is not None:
                return None
        if view.pos in view.frontier(traps=True):
            # Standing here did not reveal the unknown neighbour (a dark wall or
            # corner): walking back to it would ping-pong forever (round 11).
            self.level.dead_frontier.add(view.pos)
        trail = self.level.explore_trail
        trail.append(view.pos)
        del trail[:-EXPLORE_PINGPONG]
        if len(trail) == EXPLORE_PINGPONG and len(set(trail)) <= 2:
            # Back and forth between two squares, each step toward the other's
            # frontier: nothing is revealed by either (M5b round 46, seed 1015:
            # 5,000 steps at a dark corridor bend while the way up lay behind
            # a secret door). Drop that frontier; search takes over.
            near = {p for p in view.frontier(traps=True) if any(chebyshev(p, t) <= 1 for t in trail)}
            self.level.dead_frontier |= set(trail) | near
            trail.clear()
        frontier = view.frontier() - self.level.dead_frontier
        step = view.step_toward(frontier, avoid_monsters=True) if frontier else None
        if step is None:   # the only way on is across a known trap
            step = view.step_toward(view.frontier(traps=True) - self.level.dead_frontier,
                                    avoid_monsters=True)
        if step is not None and step != (0, 0):
            target = (view.pos[0] + step[0], view.pos[1] + step[1])
            slow = {p for p, c in view.creatures.items()
                    if (c.glyph, c.level) in knowledge.slow_kinds() and not self.coins_worth_it(c, obs)}
            slow |= {p for p, seen in self.level.slow_seen.items() if obs.step - seen < SLOW_MEMORY}
            if any(chebyshev(target, p) <= 1 for p in slow):
                # Back beside the slow creature just walked away from: the
                # way on is past it, so leave it to the stairs instead (M4
                # round 78: seed 1026 alternated walking away from Creeping
                # Coins and exploring back into them until it died). Out of
                # the torch's light it is remembered, not seen (round 85:
                # seed 1002).
                return None
        return self.move(view, step, "explore", "path to the nearest unexplored edge")

    def ranged_at(self, obs: Observation, view: View, pos: Pos) -> Decision | None:
        """Attack the creature at ``pos`` from where the player stands, with
        what it carries: an attack spell, an attack wand, the launcher, a
        flask of oil (the lantern's keep stays). A blocker is killed so: a
        Floating Eye's gaze holds only what stands beside it, and characters
        waited by eyes while lice wandered near (maintainer, 2026-11-07:
        "kill all the monsters with all the tools we have available")."""
        creature = view.creatures.get(pos)
        step = self.line_to(view, pos, missile=True) if creature is not None else None
        if step is None or step == (0, 0):
            return None
        far = chebyshev(pos, view.pos)
        glyph = creature.glyph
        attack = self.mage_attack(obs, creature) if self.magic.caster(obs) else None
        if attack is not None:
            self.pending, self.aimed = DIRS[step], (pos, glyph)
            return Decision(*self.magic.pray(attack, f"the '{glyph}' blocks the way: cast {attack} at it"))
        wands = [w for w in ATTACK_WANDS if self.wands.get(w, 0) > 0]
        if wands:
            wand = min(wands, key=ATTACK_WANDS.get)   # the weakest does for a blocker
            self.picking, self.listed, self.pending, self.last_aimed = wand, False, DIRS[step], wand
            return Decision(KEY_AIM, "fight", f"the '{glyph}' blocks the way: aim the {wand} at it")
        if self.launcher is not None and self.ammo > 0 and far <= min(FIRE_RANGE, LAUNCHERS[self.launcher][2]):
            if not self.wielding_launcher:
                self.picking, self.listed, self.wielding_launcher = self.launcher, False, True
                return Decision(KEY_WEAR, "fight", f"the '{glyph}' blocks the way: wield the {self.launcher}")
            self.pending, self.aimed = DIRS[step], (pos, glyph)
            self.ammo -= 1
            self.missiles["shots"] += 1
            self.fired = True
            return Decision(KEY_FIRE, "fight", f"the '{glyph}' blocks the way: fire the {self.launcher} at it")
        keep = OIL_RESERVE if self.lamp or self.lamp_packed else 0
        if self.oil > keep and far <= THROW_RANGE:
            self.picking, self.listed, self.pending = OIL, False, DIRS[step]
            self.aimed = (pos, glyph)
            return Decision(KEY_THROW, "fight", f"the '{glyph}' blocks the way: throw oil at it")
        return None

    @staticmethod
    def beside(view: View, pos: Pos) -> set[Pos]:
        """The squares next to ``pos`` the player can stand on: a path takes a
        goal square as reached whatever it is, and a level-1 Warrior walked
        into the wall beside a ',' 200 times in 825 steps (2026-11-06)."""
        return {(pos[0] + dx, pos[1] + dy) for dx, dy in DIRS
                if view.passable(pos[0] + dx, pos[1] + dy, avoid_monsters=False, doors=True)}

    def chosen_blocker(self, obs: Observation, view: View) -> Decision | None:
        """A blocker clear_way chose, still there, before any other walk: from
        beside it a path past it counts, so a walk stepped away and the next
        step came back (2026-11-06: a ',' on DL19 with explore, 91 approaches
        in 1,800 steps; a ',' on DL1 with the walk for light, 92 in 278)."""
        if self.level.clear_target not in {**self.level.stationary, **view.creatures}:
            return None
        return self.clear_way(obs, view)

    def clear_way(self, obs: Observation, view: View) -> Decision | None:
        """A creature that never moves (or is never meleed) stands in the only
        way to any exit or unexplored edge: kill it when the monster lore says
        it is weak, rather than search walls behind it (M4 round 70: seed
        1021 rested 9,600 turns behind a Floating Eye in a DL1 corridor and
        starved; VMS Moria's eye has 3d6 HP and a harmless gaze)."""
        if obs.dlvl == 0 or self.afraid:
            return None

        def exits() -> set[Pos]:
            return (view.frontier() - self.level.dead_frontier) | view.stairs_up() | view.stairs_down()
        # Kept once chosen, until it is gone: a step toward it stands next to
        # the square beside it, from where a path past it counts (the start
        # may be beside a monster, no later square may), so the next step
        # walked back to search and the next came again (2026-11-06: four
        # games, 'e' and ',', 100 entries of one square in 550-830 steps).
        # A creature that never moves is remembered out of the light, so the
        # commitment holds there too (2026-11-06: a ',' in a dark corridor,
        # seen every other step, 100 approaches between 100 stair walks).
        known = {**self.level.stationary, **view.creatures}
        committed = self.level.clear_target if self.level.clear_target in known else None
        self.level.clear_target = committed
        if committed is None and view.step_toward(exits(), avoid_monsters=True) is not None:
            return None
        # Measured from where the fight will be: from the player, each step
        # toward a committed blocker brought a mover into range and the next
        # walked back out (2026-11-06: a ',' on DL19, 94 approaches).
        if committed is not None:
            ranged = self.ranged_at(obs, view, committed)   # from here, whatever moves near it
            if ranged is not None:
                return ranged
        calm_from = committed if committed is not None else view.pos
        # A slow one only matters beside a paralysing gaze (below); else it
        # is fought or outwalked: worm masses wandering near a ',' turned
        # characters back from it 100 times in 400-1,200 steps (2026-11-06).
        slow = knowledge.slow_kinds()
        gaze = (known[committed].glyph in AVOID_GLYPHS if committed is not None
                else any(c.glyph in AVOID_GLYPHS for c in view.creatures.values()))
        if any(chebyshev(p, calm_from) <= CLEAR_WAY_CALM and not self.stationary(c)
               and c.glyph not in AVOID_GLYPHS and not self.still_there(p, obs)
               and (gaze or (c.glyph, c.level) not in slow) for p, c in view.creatures.items()):
            # Not while something else is coming: paralysed beside an eye,
            # the bot was eaten by the Creeping Coins it had walked away from
            # (M4 round 78, seed 1040). One asleep is not coming: a giant on
            # one square, seen only from inside the room, turned a level-23
            # Gnome back from an eye 100 times in 850 steps (C64 Balrog,
            # 2026-11-06).
            if committed is not None:
                # Chosen: wait here for it to come or go, not walk off and
                # back as it shows and hides (2026-11-06: worm masses by an
                # eye, 81 approaches and 75 stair walks in 571 steps). Not
                # for ever: then that blocker waits a while.
                # Counted for the blocker, not in a row: a calm step between
                # waits reset a run count, and lice by an eye kept it from
                # ever giving up (2026-11-07: 100 entries in 467 steps).
                waits = self.level.clear_waits[committed] = self.level.clear_waits.get(committed, 0) + 1
                if waits <= CLEAR_HOLD:
                    return Decision(KEY_REST, "fight",
                                    f"the '{known[committed].glyph}' blocks the only way on: wait, something moves near it")
                self.level.clear_skip[committed] = obs.step + CLEAR_SKIP
                self.level.clear_waits[committed] = 0
                self.level.clear_target = None
            return None
        bound = STRONG_HP_BASE + STRONG_HP_PER_LEVEL * obs.clvl
        creatures, hazards = view.creatures, view.hazards
        if committed is not None:
            creature = known[committed]
            if chebyshev(committed, view.pos) == 1:
                self.last_attack = (committed, creature.glyph)
                return Decision(DIRS[(committed[0] - view.pos[0], committed[1] - view.pos[1])], "fight",
                                f"the '{creature.glyph}' blocks the only way on: attack it")
            beside = self.beside(view, committed)
            # The squares beside it are next to a monster, which an avoiding
            # path may refuse one step short of them (2026-11-06: a C128 game
            # stepped up toward a ',' and back down 95 times). Nothing else
            # moves close (CLEAR_WAY_CALM above): go on past the rule.
            step = (view.step_toward(beside, avoid_monsters=True)
                    or view.step_toward(beside, avoid_monsters=False))
            decision = self.move(view, step, "fight", f"the '{creature.glyph}' blocks the only way on: approach it")
            if decision is not None:
                return decision
            self.level.clear_target = None
        slow = knowledge.slow_kinds()
        for pos in sorted(creatures, key=lambda p: chebyshev(p, view.pos)):
            creature = creatures[pos]
            if obs.step < self.level.clear_skip.get(pos, 0):
                continue   # waited for too long lately
            # A slow one in the way too: walked away from and back to, a
            # level-22 Warrior went 26 squares west and 28 east along one DL2
            # corridor 300 times (C128, 2026-11-07).
            if not (self.stationary(creature) or creature.glyph in AVOID_GLYPHS
                    or (creature.glyph, creature.level) in slow) or \
                    knowledge.strength().get((creature.glyph, creature.level), (0.0, 0))[0] > bound:
                continue
            # Without it: the edge beside it counts again (no frontier square
            # is next to a hazard), as do paths past it (M4 round 73: seed
            # 1006 searched a room 12,000 turns, a Floating Eye beside its
            # only door).
            view.creatures = {p: c for p, c in creatures.items() if p != pos}
            view.hazards = hazards - {pos}
            try:
                cut = view.step_toward(exits(), avoid_monsters=True) is not None
                step = None if not cut or chebyshev(pos, view.pos) == 1 else view.step_toward(
                    self.beside(view, pos), avoid_monsters=True)
            finally:
                view.creatures, view.hazards = creatures, hazards
            if not cut:
                continue
            ranged = self.ranged_at(obs, view, pos)
            if ranged is not None:
                self.level.clear_target = pos
                return ranged
            if chebyshev(pos, view.pos) == 1:
                self.last_attack = (pos, creature.glyph)
                return Decision(DIRS[(pos[0] - view.pos[0], pos[1] - view.pos[1])], "fight",
                                f"the '{creature.glyph}' blocks the only way on: attack it")
            decision = self.move(view, step, "fight", f"the '{creature.glyph}' blocks the only way on: approach it")
            if decision is not None:
                self.level.clear_target = pos
            return decision
        # Sealed in: no search spot is next to a creature that never moves,
        # so a weak one, seen or remembered, may hide the secret door: kill it
        # (M4 round 91: seed 1006 searched 21,700 turns, a remembered
        # stationary creature beside the square under the only door).
        if not self.sealed(view):
            return None
        stationary = dict(self.level.stationary)
        stationary.update({p: c for p, c in creatures.items() if self.stationary(c) or c.glyph in AVOID_GLYPHS})
        for pos in sorted(stationary, key=lambda p: chebyshev(p, view.pos)):
            creature = stationary[pos]
            if knowledge.strength().get((creature.glyph, creature.level), (0.0, 0))[0] > bound:
                continue
            if chebyshev(pos, view.pos) == 1:
                self.last_attack = (pos, creature.glyph)
                return Decision(DIRS[(pos[0] - view.pos[0], pos[1] - view.pos[1])], "fight",
                                f"sealed in: kill the '{creature.glyph}' beside the walls to search")
            step = view.step_toward(self.beside(view, pos), avoid_monsters=True)
            decision = self.move(view, step, "fight", f"sealed in: approach the '{creature.glyph}' to kill it")
            if decision is not None:
                self.level.clear_target = pos   # kept while it is in view (above)
                return decision
        return None

    def sealed(self, view: View) -> bool:
        """No stairs and no unexplored edge are reachable: only a secret door
        can let the player out. Edges already stood on that revealed nothing
        are no way out (M4 round 52: seed 1005 counted a felt-out dead-end
        corridor as an exit, rested 2,700 turns and starved)."""
        exits = (view.frontier() - self.level.dead_frontier) | view.stairs_up() | view.stairs_down()
        return view.step_toward(exits, avoid_monsters=False) is None

    def search(self, obs: Observation, view: View, *, forced: bool = False,
               per_spot: int = SEARCHES_PER_SPOT) -> Decision | None:
        """Secret doors only matter when the goal needs somewhere unreached (depth),
        or when the level has no known exit at all (``forced``). Never while
        something unseen attacks: searching stands still (round 21)."""
        if self.unseen_attack or obs.step < self.level.unseen_until:
            # Also for a while after: a caster out of sight keeps casting at a
            # player standing still (M4 round 90: seed 1013 searched a dead
            # end under a Novice Priest's wound spells until dead).
            return None
        if not forced:
            if self.level.scum or obs.dlvl == 0 or obs.dlvl >= self.goal.target_dlvl:
                return None
            if sum(self.level.searches.values()) >= SEARCH_BUDGET:
                self.level.scum = True
                return None
        searched = {p for p, n in self.level.searches.items() if n >= per_spot}
        if per_spot == SEALED_SEARCHES:
            spots = sealed_search_spots(view, searched)
        else:
            spots = view.search_spots(searched)
            if view.step_toward(spots, avoid_monsters=True) is None:
                spots = view.search_spots(searched, traps=True)
        hazards = self.hazards(view)
        spots = {s for s in spots if all(chebyshev(p, s) > 1 for p in hazards)}   # M4 round 1
        if view.pos in spots:
            self.level.searches[view.pos] = self.level.searches.get(view.pos, 0) + 1
            return Decision(KEY_SEARCH, "search", "dead end: search for a secret door")
        return self.move(view, view.step_toward(spots, avoid_monsters=True), "search",
                         "go to a wall with unexplored space behind it")

    def stair_scum(self, obs: Observation, view: View) -> Decision | None:
        """Leave an exhausted level for a fresh one: up, or down only while the
        goal still wants depth (never deeper than the goal needs)."""
        if obs.dlvl == 0:
            return None
        deeper_ok = self.deeper_ok(obs)
        here = view.type_at(*view.pos)
        # Ready for more depth, a known down staircase beats the nearest one:
        # up undid the goal's progress (M5b round 34: a level-9 Dwarf Priest
        # climbed from DL2 93 times by the nearest stairs).
        down = view.stairs_down() if deeper_ok else set()
        if (here == TYPE_STAIRS_UP and not down) or (here == TYPE_STAIRS_DN and deeper_ok):
            return Decision(ord("<") if here == TYPE_STAIRS_UP else ord(">"), "stair-scum",
                            "level exhausted: take the stairs to a fresh level")
        for exits in (down, view.stairs_up()):   # down when ready, else (or unreachable) up
            if exits:
                decision = self.move(view, self.committed_step(view, exits), "stair-scum",
                                     "level exhausted: path to the nearest staircase")
                if decision is not None:
                    return decision
        if self.food_low() or self.stuck(view):
            # No way up and short of food (M4 round 39: seeds 1002, 1004, 1019,
            # 1020 searched sealed pockets until they starved): down first.
            # Stuck too: the walls of a big level are never all searched, and
            # a level-21 Paladin searched one DL1 74,000 steps with a down
            # staircase in view (C128, 2026-11-06).
            decision = self.down_to_climb_back(view)
            if decision is not None:
                return decision
        per_spot = SEALED_SEARCHES if self.sealed(view) else SEARCHES_PER_SPOT
        decision = self.search(obs, view, forced=True, per_spot=per_spot)
        if decision is not None or obs.dlvl >= self.goal.target_dlvl:
            return decision
        # No way up and nothing left to search (§14.3 round 4): go down even if
        # not ready, then climb straight back to a fresh level (``resupply``).
        return self.down_to_climb_back(view)

    def hopping_out(self) -> bool:
        """Down-and-back hops that never got higher: arriving by up stairs is
        on a down staircase, so the next level up is no nearer. A level-27
        Priest hopped DL3-DL4 and then stood in the dark 2.4 million steps,
        two Words of Recall in its pack (C64 Balrog, 2026-11-06). Stuck
        then with no Recall to read: hop again, or a level-12 Warrior
        walked to a down staircase it would not take and searched dead ends,
        27,000 steps on one DL3 (C128, same day)."""
        if self.climb_hops >= CLIMB_HOPS and self.level.since_progress >= STUCK_STEPS and not self.recall:
            self.climb_hops = 0
        return self.climb_hops >= CLIMB_HOPS

    def climb_hop(self, view: View, why: str) -> Decision:
        if self.climb_from is None:
            self.climb_from = view.dlvl
        self.climb_hops += 1
        return Decision(ord(">"), "stair-scum" if why.startswith("no way up") else "resupply", why)

    def down_to_climb_back(self, view: View) -> Decision | None:
        if self.hopping_out():
            return None   # Word of Recall (recall_trip), or explore for the way up
        if view.type_at(*view.pos) == TYPE_STAIRS_DN:
            return self.climb_hop(view, "no way up: take the down stairs to climb back")
        return self.move(view, view.step_toward(view.stairs_down(), avoid_monsters=True), "stair-scum",
                         "no way up: path to the down stairs")
