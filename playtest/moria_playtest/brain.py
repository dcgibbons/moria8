"""Brain v1 (§6.6): deterministic, explainable, only what the current goals need.

Layers, first match wins: prompt (and store) -> retreat -> look -> throw -> fight -> eat
-> light -> resupply -> rest -> shop -> descend -> hunt -> explore -> search -> stair-scum. Every
decision records (layer, reason, key). The brain reads only the fair-play
``View``, the observation's mode, stage, status line, HP and depth, and the
player knowledge in ``knowledge`` (creature names).
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

from . import knowledge
from .magic import BLIND, BOOK_LEVELS, book_of, store_name, CHANT, CREATE_FOOD, ORB, PORTAL, SANCTUARY, FIRST_BOOK, PRAYER_BOOKS, CURE_LIGHT, CURE_MEDIUM, DETECT_DOORS, HEALS, REMOVE_FEAR, Magic
from .magic import MAGIC_MISSILE, PHASE_DOOR
from .game import ITEM_PROMPT, KEY_RUNSTOP, KEY_SPACE, Game, Mode, Observation
from .goals import CLASSES, RACE_KEYS, Goal
from .view import (DIRS, TYPE_DOOR_CLOSED, TYPE_STAIRS_DN, TYPE_STAIRS_UP, TYPE_TRAP, UNKNOWN, WALKABLE_TYPES,
                   Creature, Pos, View, sealed_search_spots)

KEY_BASH = 0x02          # CTRL+B
KEY_REST = ord("5")      # rest one turn (waiting for a first strike)
KEY_AUTOREST = 0x12      # CTRL+R: rest until recovered or disturbed (TRN-007); heals at
                         # the doubled VMS resting rate (TRN-009)
KEY_EAT = 0xC5           # SHIFT+E
KEY_SEARCH = ord("S")
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
KEEP_PREFIXES = ("Ration", "Slime Mold", "Flask of Oil", "Wooden Torch", "Brass Lantern", "Potion of Cure",
                 "Scroll of Word of Rec", "Scroll of Phase Door", "Holy Book", "Spellbook")
DROP_RETRY = 500         # steps before looking for junk again after finding none
KEY_RETURN = 0x0D
LOOK_RESULT = re.compile(r"You see an? (.+?)\.")
SLAIN = re.compile(r"You have slain the (.+?)\.")
AVOID_GLYPHS = {"e"}     # Floating Eye: paralysing gaze when meleed
RETREAT_HP = 0.60
RETREAT_RANGE = 12       # farthest staircase worth running for; beyond, fight (round 28)
TRAP_HP = 0.50           # below this share of HP a known trap is impassable (round 20)
BUMP_STEPS = 10          # steps a tile stays blocked after a move into it went nowhere
UNSEEN_STEPS = 20        # steps an attack from something unseen keeps the bot from resting (M4)
OSCILLATION_STEPS = 6    # command stops alternating between two squares before one is blocked (M4)
NEAR_STEPS = 5           # steps a creature seen within 2 squares keeps the bot from resting (M4)
STILL_LAYERS = ("fallback", "rest", "search", "hunt", "stair-scum")   # layers that may stand still
STRONG_HP_BASE, STRONG_HP_PER_LEVEL = 20, 4   # more average HP than base + this x character level: too strong
STRONG_AC_BASE, STRONG_AC_PER_LEVEL = 20, 3   # ... or more AC than base + this x character level
DETECT_EVERY = 2000      # steps between Detect Doors/Stairs prayers on one level (M5b)
BREEDERS_LEAVE = 3       # breeding creatures in view at which the level is left (M5b)
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
SLOW_MEMORY = 30         # steps a slow creature out of sight still counts as a hazard (M4 round 47)
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
BOOK_GOLD = {"Words of Wisdom": 110, "Chants and Blessings": 330, "Exorcism": 880}   # base price + 10% (M5b)
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
MISSILE_CLASSES = ("rogue", "ranger")   # the best missile skills (core/tables.s: 66, 72)
AMMO_RESERVE = 20        # shots carried
FIRE_RANGE = 8           # farthest in-line creature fired at
LAUNCHER_KEEP = 20       # gold kept back from the first launcher (later ones: the gear reserve)
STARTING_ARMOUR = {"ICAT_ARMOR": 4}           # Leather Armor [4,+0]; AC worn per armour slot
ARMOUR_SLOTS = ("ICAT_ARMOR", "ICAT_SHIELD", "ICAT_HELM", "ICAT_GLOVES", "ICAT_BOOTS")
STAT = re.compile(r"\b(ST|DX):\s*(\d+)(?:/(\d+|\*\*))?")
GEAR_ARMOUR = re.compile(r"^(.+?) \[(\d+)(?:,\s*([+-]\s*\d+))?")
GEAR_WEAPON = re.compile(r"^(.+?)(?: \(([+-]\d+),\s*([+-]\d+)\))?\s*$")
TEMPLE = 3               # store index (entrance "4"): potions and scrolls, named since stores identify stock
ALCHEMIST = 4            # store index (entrance "5"): VMS stocks Word of Recall 3 times in 21 there
BLACK_MARKET = 6         # store index (entrance "7"): everything, at a premium
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
STATUS_GOLD = re.compile(r"AU:\s*(\d+)")
STATUS_AC = re.compile(r"AC:\s*(-?\d+)")
CLW = "Potion of Cure Light"   # Cure Light Wounds (the store line may cut the name short)
CLW_SAVING = 2           # ... while saving for a prayer book (M5b)
CLW_RESERVE = 5          # potions to carry for a fight gone wrong (M4; 3 until round 56, when
                         # most deaths came after drinking all three and gold was plentiful)
PHASE = "Scroll of Phase Door"   # a short teleport (VMS teleport(10)), at the Alchemist
PHASE_RESERVE = 3        # scrolls to carry for a fight with no step out (M5b)
PHASE_GOLD = 20          # gold worth an Alchemist trip for one (base 15 gp)
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
FOOD_MAX = 20            # rations' worth to carry at most (10 until M4 round 80: items stack
                         # now, so food no longer fills the pack; maintainer: "carry more food")
RESTOCK_WAIT = 1500      # steps to keep playing after a town visit found no food
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
ORB_RANGE = 6            # farthest in-line creature Orb of Draining is aimed at (M5b)
BLIND_TURNS = 10         # Blind Creature confuses for 10 turns (MX_CONFUSE): not again before
CHANT_ODDS = 0.4         # fight odds from which a coming fight is worth a Chant
CHANT_TURNS = 24         # Chant blesses 24-47 turns: counted from its shortest
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


STORE_ITEM = re.compile(r"^\s*([a-l])\) (?:\d+ )?(\S.*?)\s+(\d+) GP")   # a stack shows its count first
PACK_ITEM = re.compile(r"^\s*([a-v])\) (?:\d+ )?(\S.*)")   # a stack shows its count first


def ready_level(dlvl: int, margin: int = 2) -> int:
    """Character level a player wants before entering ``dlvl``. Deaths kept
    clustering at the minimum: level n on DL n through round 17, so DL2 needs
    level 3 (round 18); then level 4 on DL3, so DL n >= 3 needs n + 2
    (round 24). DL1 is where a new character starts. A goal's ``margin``
    lowers that: depth goals do not need the XP (M4 round 60)."""
    if dlvl <= 1:
        return 1
    return dlvl + margin - (1 if dlvl == 2 and margin else 0)


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
    glyphs: dict[Pos, str] = field(default_factory=dict)   # unidentified glyphs seen, on screen or not
    retreat_path: set[Pos] = field(default_factory=set)   # tiles the current retreat crossed
    retreat_failed: bool = False    # it doubled back: stand and fight until it ends
    bumped: dict[Pos, int] = field(default_factory=dict)   # tile -> step it is blocked until
    collected: set[Pos] = field(default_factory=set)   # tiles a pickup was tried on, or given up
    collect_walks: dict[Pos, int] = field(default_factory=dict)   # walk decisions toward each
    slow_seen: dict[Pos, int] = field(default_factory=dict)   # slow creature tile -> step last seen
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
        self.pending_item: int | None = None   # answer for the next item prompt
        self.waited = 0                        # first-strike waits for the current target
        self.unseen_attack = False             # attacked this turn with nothing in view
        self.attacked = False                  # attacked this turn (any message naming an attack)
        self.trail: list[Pos] = []             # recent command-stop positions (oscillation check)
        self.no_food = False                   # "You have no food." until food is bought or picked up
        self.shopped = False                   # done shopping on this town visit
        self.potions_done = False              # done at the Temple on this town visit
        self.market_done = False               # done at the Black Market on this town visit
        self.alchemist_done = False            # done at the Alchemy shop on this town visit
        self.armoury_done = False              # done at the Armoury on this town visit
        self.weapons_done = False              # done at the Weaponsmith on this town visit
        self.weapon = STARTING_WEAPON          # (kind, to-dam) wielded or bought to wield
        self.launcher: str | None = None       # the launcher carried (M5d)
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
        self.at_store: int | None = None       # store the last walk into town led to
        self.clw = 0                           # Cure Light Wounds potions carried
        self.phase = 0                         # Phase Door scrolls carried
        self.shop_buys = 0                     # purchases started on this town visit
        self.store_letter: str | None = None   # item letter for the next "Buy which item?"
        self.pending_look: tuple[Pos, str] | None = None   # glyph the last look aimed at
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
        self.picking: str | None = None        # item to pick at the next item prompt (wear, throw)
        self.listed = False                    # the wear prompt's item list is showing
        self.resupply_after = 0                # step before which town is not worth a trip
        self.recall_trip_after = 0             # ... for Word of Recall alone (the Alchemist may have none)
        self.gear_trip_after = 0               # ... for armour and weapons alone
        self.book_trip_after = 0               # ... for a prayer book alone
        self.books_owned = {FIRST_BOOK} if goal.klass in BOOK_LEVELS else set()
        self.book_next: str | None = None      # the book wanted at the Temple this visit
        self.chant_until = 0                   # step until which Chant is counted on
        self.search_mode_after = 0             # step before which search mode is not turned on again
        self.pack_full = False                 # the game said "Your pack is full."
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
        self.fight_loss: dict[str, int] = {}   # creature name -> HP lost to it, not yet slain
        self.tough: dict[str, int] = {}        # creature name -> character level it beat the bot at
        self.collect_to: Pos | None = None     # the item tile being walked to
        self.noted_messages = ""               # message rows last counted (food, light)
        self.noted_on_prompt = False           # ... and whether on a prompt screen
        self.events: list[str] = []            # bot-quality events for the session (stalls)

    def state(self) -> dict[str, object]:
        """JSON-serializable state saved beside snapshots."""
        return {"last_dlvl": self.last_dlvl, "last_xp": self.last_xp,
                "scum": self.level.scum, "since_progress": self.level.since_progress}

    def decide(self, obs: Observation, view: View | None) -> Decision:
        messages = obs.rows[0] + obs.rows[1]
        fear_news = self.track_fear(messages)   # on every screen: -more- too (round 14)
        if "Your spell fails." in messages:
            if self.magic.last == CHANT:
                self.chant_until = 0           # not chanted: pray it again
            elif self.magic.last == BLIND:
                self.level.blind_until = 0
        self.magic.note(messages)
        # An attack shown only behind -more- (while paralysed) still counts on
        # the next command screen, which may say no more than "You can move
        # again." (M4 round 51: seeds 1006, 1007 rested beside a White
        # Mushroom patch until it killed them).
        self.recent_attacker = knowledge.attacker(messages) or self.recent_attacker
        if not (messages == self.noted_messages and self.noted_on_prompt):
            # Food and light news on every screen too: a third message pushes
            # earlier ones behind -more- (review). A screen repeating what a
            # prompt screen just showed is not news; repeats between command
            # screens are (two pickups in a row read the same).
            self.count_food(messages)
            self.track_light(messages)
            if "Your pack is full." in messages:
                self.pack_full = True
            self.track_missiles(messages)
        self.noted_messages, self.noted_on_prompt = messages, obs.mode != Mode.COMMAND
        if obs.mode != Mode.COMMAND:
            return self.prompt(obs)
        assert view is not None
        self.pending = self.pending_item = self.picking = None   # their prompts are past
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
        self.note_toughness(obs, attacker, messages)
        if self.last_attack is not None and self.last_attack[0] == view.pos:
            # The attack walked onto the tile: nothing was there (round 20).
            self.level.identified[self.last_attack] = ("item", self.last_attack[1])
        self.last_attack = None
        self.remember_glyphs(view)
        self.identify(view, messages, attacker)
        self.remember_stationary(view)
        # Slow creatures not worth a fight are kept at a distance like the
        # stationary ones: explore stepped back beside retreated-from coins
        # every other turn (M4 round 46, seed 1002).
        slow = {p for p, c in view.creatures.items()
                if c.glyph in knowledge.slow_glyphs() and not self.coins_worth_it(c, obs)}
        self.level.slow_seen.update(dict.fromkeys(slow, obs.step))
        view.hazards = set(self.level.stationary) | {
            p for p, seen in self.level.slow_seen.items() if obs.step - seen < SLOW_MEMORY}
        if any(self.outmatched(c, obs) for c in view.creatures.values()):
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
        decision = self.choose(obs, view)
        decision = self.shun_stationary(obs, view, decision)
        decision = self.break_oscillation(obs, view, decision)
        if decision.key in DIRS.values() and decision.layer not in ("fight", "look", "prompt"):
            step = next(d for d, k in DIRS.items() if k == decision.key)
            self.last_move = (view.pos, (view.pos[0] + step[0], view.pos[1] + step[1]))
        return decision

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
        for layer in (self.search_mode, self.drop_junk, self.swat, self.quaff, self.pray, self.invoke, self.shoot, self.throw, self.crowded, self.shun, self.retreat, self.phase_door, self.look,
                      self.fight, self.eat,
                      self.light,
                      self.wear,
                      self.recall_trip, self.resupply,
                      self.rest, self.collect,
                      self.shop, self.descend, self.hunt, self.explore, self.clear_way, *last):
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
        if obs.mode == Mode.DISMISS:
            return Decision(KEY_SPACE, "prompt", f"dismiss {obs.stage}")
        if obs.mode == Mode.DEATH:
            return Decision(KEY_SPACE, "prompt", "death flow")
        if obs.mode == Mode.STORE:
            return self.store(obs)
        if obs.mode == Mode.SPELL:
            return Decision(*self.magic.prompt(obs))
        if obs.mode == Mode.DIRECTION and self.pending is not None:
            key, self.pending = self.pending, None
            return Decision(key, "prompt", "direction for the pending action")
        if self.pending_item is not None and "which" in obs.rows[0]:
            key, self.pending_item = self.pending_item, None
            return Decision(key, "prompt", "first matching item")
        if obs.mode == Mode.ITEM:
            return Decision(KEY_RUNSTOP, "prompt", f"cancel item prompt ({obs.stage})")
        return Decision(KEY_RUNSTOP, "prompt", f"cancel unknown prompt {obs.stage}".strip())

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
            if self.bought is not None:
                self.credit(self.bought, -1)   # the counted purchase did not happen
            self.bought = None
            self.leave_store(obs)   # cannot afford it or pack full: stop buying
            return Decision(KEY_SPACE, "shop", "acknowledge the store message")
        self.bought, self.typing = None, []
        done = {TEMPLE: self.potions_done, BLACK_MARKET: self.market_done, ARMOURY: self.armoury_done,
                WEAPONSMITH: self.weapons_done, ALCHEMIST: self.alchemist_done}.get(self.at_store, self.shopped)
        if obs.stage == "menu" and not done and self.at_store in (ARMOURY, WEAPONSMITH):
            pick = self.missile_pick(obs) if self.at_store == WEAPONSMITH else None
            pick = pick or self.gear_pick(obs)
            if pick is not None:
                self.store_letter, self.buying = pick
                return Decision(ord("B"), "shop", f"buy {pick[1]}")
        elif obs.stage == "menu" and not done:
            gold = re.search(r"Gold: (\d+)", obs.rows[16])
            for want in self.shopping_list(int(gold.group(1)) if gold else None):
                for row in obs.rows[3:15]:
                    match = STORE_ITEM.match(row)
                    if match and match.group(2).startswith(want) and \
                            (gold is None or int(match.group(3)) <= int(gold.group(1))):
                        self.store_letter, self.buying = match.group(1), match.group(2)
                        if want in FOODS:
                            self.shop_buys += 1
                        return Decision(ord("B"), "shop", f"buy {match.group(2)}")
        self.leave_store(obs)
        return Decision(ord("Q"), "shop", f"leave the store ({obs.stage})")

    def leave_store(self, obs: Observation) -> None:
        """The Alchemist is done once left; the General Store keeps its food
        and light bookkeeping (``end_visit``)."""
        if self.at_store == TEMPLE:
            self.potions_done = True
        elif self.at_store == BLACK_MARKET:
            self.market_done = True
        elif self.at_store == ALCHEMIST:
            self.alchemist_done = True
        elif self.at_store == ARMOURY:
            self.armoury_done = True
        elif self.at_store == WEAPONSMITH:
            self.weapons_done = True
        else:
            self.end_visit(obs)

    def end_visit(self, obs: Observation) -> None:
        """Shopping is over for this visit, however it ended (round 20: a
        refused purchase skipped this and hopped forever)."""
        if self.shopped:
            return
        self.shopped = True
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
        food_max = FOOD_EARLY_MAX if self.clvl < EARLY_LEVELS else FOOD_MAX
        if self.shop_buys < FOOD_PER_VISIT and self.food < food_max:
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
        if self.recall < self.recall_reserve():
            wants.append(RECALL)
        if self.phase < PHASE_RESERVE:
            wants.append(PHASE)
        if self.launcher is not None and self.ammo < AMMO_RESERVE:
            wants.append(LAUNCHERS[self.launcher][0])   # 1-2 gp a shot
        if self.at_store == TEMPLE and self.book_next is not None:
            wants.insert(0, store_name(self.book_next))   # a caster's prayers first (maintainer, 2026-10-25)
        if self.at_store == BLACK_MARKET:
            wants = [w for w in wants if w == RECALL]   # nothing else is wanted there
        elif self.at_store == ALCHEMIST:
            wants = [w for w in wants if w in (RECALL, PHASE)]
        return wants

    def stats(self, obs: Observation) -> tuple[int, int]:
        """Strength and dexterity from the status lines (18/xx as 18 + xx/10)."""
        found = {}
        for row in obs.rows[19:24]:
            for name, base, extra in STAT.findall(row):
                found[name] = int(base) + (10 if extra == "**" else int(extra) // 10 if extra else 0)
        if "ST" in found:
            self.last_stats = (found["ST"], found.get("DX", 10))
        # A store screen shows no stats: the last ones seen, not a default.
        # With STR 10 assumed there, a weaker Human Priest bought a 15 lb
        # Morningstar and hit 66 times in 377 swings (M5b round 50).
        return self.last_stats

    def melee_score(self, name: str, to_dam: int, obs: Observation) -> float:
        """Expected melee damage a turn before to-hit: blows (Umoria's table,
        ``combat_calc_blows``) times the dice average plus the to-dam bonus."""
        kind = knowledge.item_kinds().get(name)
        if kind is None or not kind.melee:
            return 0.0
        strength, dexterity = self.stats(obs)
        return knowledge.blows(strength, dexterity, kind.weight) * (kind.dice * (kind.sides + 1) / 2 + to_dam)

    def melee_skill(self, name: str, obs: Observation) -> int:
        """To-hit skill with weapon ``name``: the class's and race's melee
        skill and its gain a level, less Umoria's too-heavy penalty, three
        a point by which the weight passes STR x 15 (``combat_calc_melee_
        total_tohit_bonus``). A Human Priest bought heavy weapons by damage
        alone and hit DL1 Kobolds 42% of the time against 66% expected
        (M5b round 16: Kobolds 16 of 20 deaths)."""
        base, per_level = CLASS_BTH[self.goal.klass]
        skill = base + RACE_BTH[self.goal.race] + per_level * obs.clvl
        kind = knowledge.item_kinds().get(name)
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
        book = self.book_wanted(obs)
        return reserve + (BOOK_GOLD.get(book, 0) if book else 0)

    def clw_reserve(self) -> int:
        """Potions to carry: fewer while saving for a wanted prayer book."""
        return CLW_SAVING if self.book_next is not None else CLW_RESERVE

    def gear_pick(self, obs: Observation) -> tuple[str, str] | None:
        """At the Armoury or Weaponsmith: the item that most improves what is
        worn in its slot, or the weapon wielded, that the gold allows while
        keeping ``GEAR_RESERVE`` (M4 round 74: characters met Green Nagas on
        DL5-9 with the starting Dagger and AC 4, carrying thousands of gold)."""
        gold = re.search(r"Gold: (\d+)", obs.rows[16])
        budget = (int(gold.group(1)) if gold else 0) - self.gear_reserve(obs)
        if self.at_store == ARMOURY and self.weapon == STARTING_WEAPON and not self.weapons_done:
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
            if self.at_store == ARMOURY:
                armour = GEAR_ARMOUR.match(name)
                kind = knowledge.item_kinds().get(armour.group(1)) if armour else None
                if kind is None or kind.category not in ARMOUR_SLOTS:
                    continue
                ac = int(armour.group(2)) + int((armour.group(3) or "0").replace(" ", ""))
                gain, change = ac - worn.get(kind.category, 0), ("armour", (kind.category, ac))
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
            self.bought = self.buying
            self.credit(self.buying, 1)

    def credit(self, item: str, n: int) -> None:
        """Count an item gained (n=1) or a counted one not gained after all (n=-1)."""
        if item.startswith(FOODS):
            self.food += n * (SLIME if item.startswith("Slime") else 1)
            self.no_food = self.no_food and n < 0
        elif item.startswith(LANTERN):
            self.lamp_packed = n > 0
        elif item.startswith(OIL):
            self.oil += n
        elif item.startswith(TORCH):
            self.torches += n
        elif item.startswith(CLW):
            self.clw += n
        elif item.startswith(RECALL):
            self.recall += n
        elif item.startswith(PHASE):
            self.phase += n
        elif item.startswith(tuple(LAUNCHERS)):
            if n > 0:
                self.launcher = next(name for name in LAUNCHERS if item.startswith(name))
                self.ammo = 0   # another launcher's ammunition does not fit it
            else:
                self.launcher = None
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

    def pick_item(self, obs: Observation) -> Decision:
        """Answer an item prompt (wear, throw): list the items, then pick by name."""
        rows = obs.rows[1:]
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
            if match and match.group(2).startswith(self.picking):
                if self.picking == OIL:
                    self.oil = max(0, self.oil - 1)   # thrown: counted once actually picked
                elif self.picking == CLW:
                    self.clw = max(0, self.clw - 1)
                elif self.picking == PHASE:
                    self.phase = max(0, self.phase - 1)
                elif self.picking == RECALL:
                    self.recall = max(0, self.recall - 1)
                    self.recalling = True
                elif self.picking in self.gear:
                    # Counted as worn only once it is in the pack to put on:
                    # a refused purchase never got there (M4: a haggled price
                    # over the gold).
                    kind, change = self.gear.pop(self.picking)
                    if kind == "weapon":
                        self.weapon = change
                    else:
                        self.armour[change[0]] = change[1]
                self.picking = None
                return Decision(ord(match.group(1).upper()), "prompt", f"pick {match.group(2).strip()}")
        if not self.listed and ITEM_PROMPT.search(obs.rows[0]):
            self.listed = True
            return Decision(ord("?"), "prompt", "list the items")
        if self.picking == OIL:
            self.oil = 0          # the pack has none, whatever the count said (M4 seed 1006)
        elif self.picking == TORCH:
            self.torches = 0
        elif self.picking == CLW:
            self.clw = 0
        elif self.picking == PHASE:
            self.phase = 0
        elif self.picking == RECALL:
            self.recall = 0
        self.picking = None
        return Decision(KEY_RUNSTOP, "prompt", "item to pick not listed: cancel")

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
        1012 stepped A-B-A-B for hundreds of steps and died there)."""
        if decision.key not in DIRS.values() or decision.layer in ("fight", "look", "prompt"):
            return decision
        # Moves only: a potion drunk between the steps put the same square in
        # the trail twice, which reads as standing still, and a Halfling
        # stepped back and forth beside a Yellow Jelly, drinking every few
        # steps, until it died (M5a round 7: 5 Yellow Jelly deaths).
        self.trail = (self.trail + [view.pos])[-OSCILLATION_STEPS:]
        if len(self.trail) < OSCILLATION_STEPS or len(set(self.trail)) != 2 or any(
                a == b for a, b in zip(self.trail, self.trail[1:])):
            return decision
        step = next(d for d, k in DIRS.items() if k == decision.key)
        target = (view.pos[0] + step[0], view.pos[1] + step[1])
        if target not in self.trail:
            return decision
        self.level.bumped[target] = obs.step + BUMP_STEPS
        view.blocked.add(target)
        self.trail = []
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
        if obs.dlvl != self.last_dlvl:
            self.last_dlvl = obs.dlvl
            self.level = LevelMemory()
            if obs.dlvl == 0:
                self.recall_trip_after = obs.step + RESTOCK_WAIT   # one try per visit: the Alchemist may have none
                self.gear_trip_after = obs.step + GEAR_TRIP_WAIT   # the stores restock slowly
                self.book_trip_after = obs.step + RESTOCK_WAIT     # the Temple may have none
            self.shopped, self.shop_buys, self.potions_done, self.market_done = False, 0, False, False
            self.armoury_done = self.weapons_done = self.alchemist_done = False
            self.recalling = False
            self.max_dlvl = max(self.max_dlvl, obs.dlvl)
            self.trip_dlvl = max(self.trip_dlvl, obs.dlvl) if obs.dlvl else 0
            self.last_move = None
        known = sum(1 for t in view.types if t != UNKNOWN)
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

    def needs_resupply(self, obs: Observation) -> bool:
        """Food or light is low and a town trip could help (not right after a
        visit that found the store without it), or the character carries no
        Word of Recall and can now afford one."""
        # A caster who can pray Create Food does not climb for food.
        low = self.light_low() or (self.food_low() and not self.magic.feeds(obs))
        return ((low and obs.step >= self.resupply_after) or self.wants_recall(obs)
                or self.wants_gear(obs) or self.wants_book_trip(obs))

    def book_wanted(self, obs: Observation) -> str | None:
        """The next prayer book not carried whose first prayer the character's
        level reaches. Books bind a caster: a prayer is learned from and prayed
        from its book, so without Words of Wisdom a Priest past level 5 learned
        nothing (M5b round 18: 239 studies found "No new spells to learn", no
        book bought; maintainer, 2026-10-25)."""
        levels = BOOK_LEVELS.get(self.goal.klass)
        if levels is None:
            return None
        owned = self.books_owned | set(self.magic.books or ())   # bought, or picked up and listed
        return next((book for book, level in zip(PRAYER_BOOKS, levels)
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
        return (not self.recall and obs.dlvl > 0 and obs.step >= self.recall_trip_after
                and self.gold(obs) >= RECALL_GOLD + GEAR_RESERVE)   # and the next trip's food and potions

    def wants_gear(self, obs: Observation) -> bool:
        """Gold enough for real armour and a while since the last town visit:
        a trip to spend it. Town trips came only for food, light or Word of
        Recall, so gold piled up below (M5a: a Half-Elf on DL5 with 1,547 gold
        and AC 7; several characters visited the Armoury once in a run), and
        Creeping Coins and nagas hit low AC hardest."""
        return obs.dlvl > 0 and obs.step >= self.gear_trip_after and self.gold(obs) >= GEAR_TRIP_GOLD

    def supplies_low(self) -> bool:
        return self.food_low() or self.light_low()

    def light_low(self) -> bool:
        refill = (self.oil if self.lamp else 0) + self.torches
        # The last torch is the light home: steps undercount its burn (search
        # mode spends two turns a step, an auto-rest many), and characters went
        # dark far from town with no Word of Recall (M5b round 45: five runs).
        return (self.light_left < LIGHT_RESERVE or not self.lamp) and not refill and not self.lamp_packed

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
        if self.trip_dlvl <= SHALLOW_DLVL:
            return SHALLOW_FOOD_RESERVE
        return FOOD_RESERVE + self.trip_dlvl // FOOD_PER_DEPTH

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

    def underleveled(self, obs: Observation) -> bool:
        """Readiness (§14.3 rounds 2, 18): not deeper before ``ready_level``.
        A level-1 character cannot survive one Cause Light Wounds (3d8) from a
        DL2 caster, so a player gains levels before going deeper. (A maximum
        HP bar, two of a depth's strongest spells, held level-4 Priests on DL1
        until level 6-7 and was removed in M5b round 36: maintainer, "that's
        your made up rule, doesn't make sense".)"""
        return obs.clvl < ready_level(obs.dlvl + 1, self.goal.ready_margin)

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
        dice against its chance to hit the character's armour."""
        match = STATUS_AC.search(obs.rows[23])
        armour = int(match.group(1)) if match else 0
        tohit = knowledge.attack_tohit()
        return sum(dice * (sides + 1) / 2
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
        attacks = knowledge.attacks()
        worst = sum(dice * sides for c in self.adjacent for _, dice, sides in attacks.get((c.glyph, c.level), ()))
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
        flee_hp = 2.0 if any(self.outmatched(c, obs) for c in near) else \
            HUNT_HP if any(c.glyph in tough or self.too_strong(c, obs) for c in near) else RETREAT_HP
        badly_hurt = close and obs.hp < flee_hp * obs.mhp
        if obs.dlvl == 0 or not (threats or unseen) or (
                not badly_hurt and obs.hp >= HUNT_HP * obs.mhp and not (self.afraid and close)):
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
        if ((self.chased and not self.unseen_attack) or self.level.retreat_failed) and not self.afraid:
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
            return None if self.out_of_food() else self.walk_away(view, threats)
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
    def walk_away(view: View, threats: set[Pos]) -> Decision | None:
        """No stairs to run for, but every close threat is slower than the
        player: step away from them (M4 round 35: seed 1008 fought a nest of
        Creeping Copper Coins down to 3 HP)."""
        close = {p for p in threats if chebyshev(p, view.pos) <= 2}
        if not close or any(view.creatures[p].glyph not in knowledge.slow_glyphs() for p in close):
            return None
        here = min(chebyshev(p, view.pos) for p in close)
        best = None
        for (dx, dy), key in DIRS.items():
            x, y = view.pos[0] + dx, view.pos[1] + dy
            if view.passable(x, y, avoid_monsters=True):
                far = min(chebyshev(p, (x, y)) for p in close)
                if far > here and (best is None or far > best[0]):
                    best = (far, key)
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
    def line_to(view: View, target: Pos) -> tuple[int, int] | None:
        """Unit step toward ``target`` when it is the first thing a look along
        that line would reach (only known floor in between)."""
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
            step = self.line_to(view, pos)
            if step is None or chebyshev(pos, view.pos) > THROW_RANGE or self.stationary(creature):
                continue
            if not self.afraid and not self.worth_oil(creature, obs):
                continue
            if not self.afraid and chebyshev(pos, view.pos) < 2 and not (early and self.melee_weak(obs)):
                continue
            self.picking, self.listed, self.pending = OIL, False, DIRS[step]
            why = "afraid" if self.afraid else "approaching"
            return Decision(KEY_THROW, "throw", f"{why}: throw oil at '{creature.glyph}'")
        return None

    def missile_pick(self, obs: Observation) -> tuple[str, str] | None:
        """At the Weaponsmith, for a class whose strength is missiles (M5d):
        a launcher better than the one carried (multiplier times its
        ammunition's average), then its ammunition. The first launcher from
        all but ``LAUNCHER_KEEP`` gold; a better one from the gold the gear
        reserve leaves."""
        if self.goal.klass not in MISSILE_CLASSES:
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
            step = self.line_to(view, pos)
            if step is None or far < 2 or far > min(FIRE_RANGE, LAUNCHERS[self.launcher][2]) \
                    or self.stationary(creature) or (creature.glyph, creature.level) in breeders:
                continue
            if not self.wielding_launcher:
                if far < 3:
                    continue   # no turn to spare for the change
                self.picking, self.listed, self.wielding_launcher = self.launcher, False, True
                return Decision(KEY_WEAR, "shoot", f"'{creature.glyph}' approaching: wield the {self.launcher}")
            self.pending = DIRS[step]
            self.ammo -= 1
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
        if not self.out_of_food() and all(view.creatures[p].glyph in knowledge.slow_glyphs()
               and not self.coins_worth_it(view.creatures[p], obs) for _, p in adjacent):
            # Creeping coins: each poison touch stacks more poison, and they
            # cannot keep up; when hurt, fight only when cornered (M4 round
            # 45: ~5 deaths a round traded blows with them).
            away = self.walk_away(view, {p for _, p in adjacent})
            if away is not None:
                return away
        _, (x, y) = adjacent[0]
        self.last_attack = ((x, y), view.creatures[(x, y)].glyph)
        return Decision(DIRS[(x - view.pos[0], y - view.pos[1])], "fight",
                        f"attack adjacent '{view.creatures[(x, y)].glyph}'")

    def rest(self, obs: Observation, view: View) -> Decision | None:
        """Rest to full HP (CTRL+R) whenever nothing that can reach the player
        is in view, nothing unseen has attacked lately, and there is food. Auto-rest stops by itself on damage, worse hunger, a
        message or anything coming into view, so the brain decides again."""
        if obs.dlvl == 0 or self.threats(view) or self.unseen_attack or obs.hp >= obs.mhp:
            return None
        slow_near = any(obs.step - seen < SLOW_MEMORY for seen in self.level.slow_seen.values())
        if obs.step < max(self.level.unseen_until, self.level.near_until) or self.no_food or slow_near:
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
            if obs.hp < RETREAT_HP * obs.mhp and self.level.last_threat is not None:
                away = self.step_away(view, self.level.last_threat)
                if away is not None:
                    return Decision(away, "rest", "hurt: back away from where it was")
            return None
        return Decision(KEY_AUTOREST, "rest", f"HP {obs.hp}/{obs.mhp} and nothing in view")

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
        if obs.dlvl == 0 or self.threats(view) or self.unseen_attack:
            self.collect_to = None
            return None
        keep_off = view.hazards | self.hazards(view)
        wanted = {p for p, (glyph, name) in self.items_seen.items()
                  if p not in self.level.collected and (glyph == COIN_GLYPH or name.startswith(FOODS)
                                                        or (self.launcher is not None
                                                            and name.startswith(LAUNCHERS[self.launcher][0])))
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
        too_deep = obs.clvl < ready_level(obs.dlvl, self.goal.ready_margin) - 1
        if view.type_at(*view.pos) == TYPE_STAIRS_UP and obs.clvl < ready_level(obs.dlvl, self.goal.ready_margin):
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
        why = (("no Word of Recall" if self.wants_recall(obs) else "gold for armour")
               if not self.supplies_low() else "light low" if not self.food_low()
               else f"{self.food:.3g} food left") \
            if self.needs_resupply(obs) else f"DL{obs.dlvl} too deep for level {obs.clvl}"
        if view.type_at(*view.pos) == TYPE_STAIRS_UP:
            return Decision(ord("<"), "resupply", f"{why}: go up")
        step = view.step_toward(view.stairs_up(), avoid_monsters=True)
        if step is None and view.step_toward(view.frontier(), avoid_monsters=True) is None:
            # No way up and nothing left to explore: a down staircase arrives on
            # an up staircase to a fresh level (round 25; searching walls
            # instead starved seed 1014).
            if view.type_at(*view.pos) == TYPE_STAIRS_DN:
                return Decision(ord(">"), "resupply", f"{why}: no way up, down to climb back")
            return self.move(view, view.step_toward(view.stairs_down(), avoid_monsters=True), "resupply",
                             f"{why}: no way up, path to the down stairs")
        return self.move(view, step, "resupply", f"{why}: path to the up stairs")

    def recall_reserve(self) -> int:
        """Word of Recall scrolls to carry. Early, one: a level-1 Paladin spent
        480 of its 570 gold on two and met DL1 Kobolds with a Dagger (M5b
        round 6); one still gets a character out of a sealed DL1-2 pocket."""
        return 1 if self.clvl < EARLY_LEVELS else RECALL_RESERVE

    def shop(self, obs: Observation, view: View) -> Decision | None:
        """In town, walk into the General Store once per visit to buy food,
        then the Alchemist for Cure Light Wounds while short of them (M4).
        Early (``EARLY_LEVELS``), a weapon and armour come before the
        Alchemist and the Temple (M5b round 6)."""
        if obs.dlvl != 0:
            return None
        early = obs.clvl < EARLY_LEVELS
        if early and self.goal.klass == "priest" and not self.armoury_done and len(view.stores) > ARMOURY \
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
        elif not self.shopped and len(view.stores) > GENERAL_STORE:
            store, why = GENERAL_STORE, "walk to the General Store for food"
        elif not self.alchemist_done and len(view.stores) > ALCHEMIST and self.recall < self.recall_reserve() \
                and self.gold(obs) >= RECALL_GOLD:
            # Word of Recall before potions: Cure Light Wounds bought first
            # left too little gold for it, and characters with none starved
            # stuck (M4 round 91: seeds 1003, 1006, 1016).
            store, why = ALCHEMIST, "walk to the Alchemy shop for Word of Recall"
        elif not self.potions_done and len(view.stores) > TEMPLE and self.temple_worth_it(obs):
            store, why = TEMPLE, "walk to the Temple for Cure Light Wounds and Word of Recall"
        elif not self.alchemist_done and len(view.stores) > ALCHEMIST and self.phase < PHASE_RESERVE \
                and self.gold(obs) >= PHASE_GOLD:
            store, why = ALCHEMIST, "walk to the Alchemy shop for Phase Door"
        elif not self.market_done and len(view.stores) > BLACK_MARKET and self.market_worth_it(obs):
            store, why = BLACK_MARKET, "walk to the Black Market for Word of Recall"
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
            return None
        if obs.dlvl == 0:
            spare = self.gold(obs) > self.gear_reserve(obs)
            ready = self.shopped and (self.potions_done or len(view.stores) <= TEMPLE) and (
                self.alchemist_done or self.recall >= self.recall_reserve() or self.gold(obs) < RECALL_GOLD) and (
                self.market_done or not self.market_worth_it(obs)) and not self.to_wear and (
                self.weapons_done or not spare) and (self.armoury_done or not spare)
            if not ready or self.max_dlvl < RECALL_FROM or self.supplies_low() or self.recall < 2:
                # The last scroll is the way home, not the way down (M5a).
                return None
        elif not (self.food_low() and self.sealed(view)) and not self.stuck(view) and not self.lightless() and (
                obs.dlvl < RECALL_FROM or not self.needs_resupply(obs)):
            # Sealed in and short of food, any depth: the only other way out
            # is a secret door the searches have not found (M4 round 53: 4
            # of 11 reach_dl10 deaths starved searching).
            return None
        self.picking, self.listed = RECALL, False
        return Decision(ord("R"), "recall", "read Word of Recall")

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
        match = STATUS_GOLD.search(obs.rows[23])
        return int(match.group(1)) if match else 0

    def wear(self, obs: Observation, view: View) -> Decision | None:
        """Wield or wear what was bought, in town before going down."""
        if obs.dlvl != 0 or not self.to_wear:
            return None
        self.picking, self.listed = self.to_wear.pop(0), False
        return Decision(KEY_WEAR, "wear", f"wear the {self.picking}")

    def market_worth_it(self, obs: Observation) -> bool:
        """A Black Market trip only for Word of Recall, with plenty of gold."""
        match = STATUS_GOLD.search(obs.rows[23])
        return self.recall < self.recall_reserve() and match is not None and int(match.group(1)) >= MARKET_GOLD

    def temple_worth_it(self, obs: Observation) -> bool:
        """A Temple trip only with the gold for what is wanted there."""
        match = STATUS_GOLD.search(obs.rows[23])
        gold = int(match.group(1)) if match else 0
        book = self.book_wanted(obs)
        return (self.clw < self.clw_reserve() and gold >= CLW_GOLD) or \
            (self.recall < self.recall_reserve() and gold >= RECALL_GOLD) or \
            (book is not None and gold >= BOOK_GOLD.get(book, 0))

    def quaff(self, obs: Observation, view: View) -> Decision | None:
        """Badly hurt with a Cure Light Wounds potion: drink it (M4), in town
        too (M5b round 3: poison drained characters there, where the bot never
        rests).

        Not beside creatures that are all slower than the player while a
        step away exists: a potion heals ~8 while a Creeping Coins nest hits
        for ~12 a turn, and stepping away costs nothing they can catch up
        to (M5a round 10: a Half-Elf drank five in a row beside them and
        died). Out of reach, the next decision drinks."""
        if not self.clw or (obs.hp >= QUAFF_HP * obs.mhp and not (
                (self.under_spell(obs, view) or self.under_blow(obs, view)) and not self.magic.can(obs, CURE_LIGHT))):
            return None
        beside = {p for p, c in view.creatures.items() if chebyshev(p, view.pos) == 1 and not self.stationary(c)}
        if beside and all(view.creatures[p].glyph in knowledge.slow_glyphs() for p in beside):
            away = self.walk_away(view, beside)
            if away is not None:
                return Decision(away.key, "retreat", "hurt beside slow creatures: step away before drinking")
        self.picking, self.listed = CLW, False
        return Decision(ord("Q"), "quaff", f"HP {obs.hp}/{obs.mhp}: drink Cure Light Wounds")

    def phase_door(self, obs: Observation, view: View) -> Decision | None:
        """Badly hurt in contact with no retreat (``retreat`` came first and
        found no step out): read Phase Door. Only beside a breeder, beside
        two or more, or near death: a Paladin stood 250 steps on one square
        killing Blue Worm masses as fast as they bred, every step out into
        contact, and died there (M5b round 11). Away from them, ``retreat``
        and ``stair_scum`` take over."""
        magic = self.magic
        beside = [c for c in self.adjacent if not self.stationary(c)]
        # An outmatched creature in contact (a naga: too strong by the lore,
        # no faster than a walk) is left before the fight, at any HP: four
        # Human Priests met DL5 Green Nagas at full HP, every step to the
        # stairs past them, and fought them to the end (M5b round 53).
        outmatched = any(self.outmatched(c, obs) for c in beside)
        if obs.dlvl == 0 or (obs.hp >= RETREAT_HP * obs.mhp and not outmatched) or not (
                self.phase or magic.can(obs, PORTAL) or magic.can(obs, SANCTUARY) or magic.can(obs, PHASE_DOOR)):
            return None
        if not beside:
            return None
        breeders = knowledge.breeder_kinds()
        if not (len(beside) >= 2 or any((c.glyph, c.level) in breeders for c in beside)
                or obs.hp < QUAFF_HP * obs.mhp or outmatched):
            return None
        if len(beside) >= 2 and magic.can(obs, SANCTUARY):
            # Sleeps every adjacent creature: the retreat then walks off.
            return Decision(*magic.pray(SANCTUARY, f"HP {obs.hp}/{obs.mhp}, {len(beside)} beside: pray Sanctuary"))
        if self.phase:
            self.picking, self.listed = PHASE, False
            return Decision(ord("R"), "phase", f"HP {obs.hp}/{obs.mhp}, no way out: read Phase Door")
        if magic.can(obs, PORTAL):
            return Decision(*magic.pray(PORTAL, f"HP {obs.hp}/{obs.mhp}, no way out: pray Portal"))
        if magic.can(obs, PHASE_DOOR):
            # The scroll first: the spell can fail (a Ranger's 35%, a Rogue's 55%).
            return Decision(*magic.pray(PHASE_DOOR, f"HP {obs.hp}/{obs.mhp}, no way out: cast Phase Door"))
        return None   # Sanctuary known, one beside: nothing that helps (M5b round 24: Portal asked 1,666 times)

    def drop_junk(self, obs: Observation, view: View) -> Decision | None:
        """A full pack refused every purchase: worn-out armour and weapons
        replaced by better ones, and burnt-out torches, stayed in it, and two
        Dwarf Priests hopped between town and DL 1 for 4,000 steps unable to
        buy food (M5b round 29). Drop one thing the bot has no use for,
        with nothing in view."""
        if not self.pack_full or obs.step < self.drop_after or self.threats(view):
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
            for row in obs.rows[1:]:
                match = PACK_ITEM.match(row)
                name = match.group(2) if match else ""
                spent = "(0 turns)" in name           # a burnt-out torch or lantern
                # The melee weapon is in the pack while the launcher is wielded.
                keep = KEEP_PREFIXES + tuple(LAUNCHERS) + tuple(AMMO_AVERAGE) + \
                    ((self.weapon[0],) if self.wielding_launcher else ())
                if match and (spent or not name.startswith(keep)) and name not in self.to_wear:
                    self.dropping = self.pack_full = False
                    if obs.dlvl == 0:
                        # Room made in town: back to the General Store, whose
                        # refused ration ended the visit (M5b round 47, seed
                        # 1014: a level-9 Dwarf starved walking between shops).
                        self.shopped = False
                    return Decision(ord(match.group(1).upper()), "prompt", f"drop {match.group(2).strip()}")
        self.dropping = self.pack_full = False
        self.drop_after = obs.step + DROP_RETRY   # nothing to spare: not again for a while
        return Decision(KEY_RUNSTOP, "prompt", "nothing to drop: cancel")

    @staticmethod
    def searching(obs: Observation) -> bool:
        """Search mode on: the status line shows "Search*" (row 21 or 23 by layout)."""
        return any("Search*" in row for row in obs.rows[21:24])

    def search_mode(self, obs: Observation, view: View) -> Decision | None:
        """Search mode while moving about with nothing in view: every step
        searches the squares around, finding traps before they spring
        (maintainer, 2026-10-25: rockfall traps killed level-1 Priests). It
        halves speed (an extra turn after each action); the game turns it off
        when a creature comes into view, on any attack or trap, and on a new
        level, as Umoria's playerDisturb does."""
        if obs.dlvl == 0 or self.searching(obs) or self.threats(view) or self.unseen_attack \
                or obs.step < self.search_mode_after:
            return None
        self.search_mode_after = obs.step + SEARCH_MODE_EVERY
        return Decision(KEY_SEARCH_MODE, "search-mode", "nothing in view: search mode on")

    def invoke(self, obs: Observation, view: View) -> Decision | None:
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
        close = sorted((p for p in self.threats(view) if not self.stationary(view.creatures[p])),
                       key=lambda p: chebyshev(p, view.pos))
        for pos in close:
            creature = view.creatures[pos]
            step = self.line_to(view, pos)
            if step is None or chebyshev(pos, view.pos) > ORB_RANGE:
                continue
            worth = knowledge.strength().get((creature.glyph, creature.level), (0.0, 0))[0] >= OIL_WORTH_HP
            if magic.spare(obs, ORB) and worth:
                self.pending = DIRS[step]
                return Decision(*magic.pray(ORB, f"pray Orb of Draining at '{creature.glyph}'"))
            if magic.spare(obs, MAGIC_MISSILE) and worth and not (
                    obs.hp < RETREAT_HP * obs.mhp and any(not self.stationary(c) for c in self.adjacent)):
                # 2d6, a flask's damage, for 1 mana (M5d). Hurt with a
                # creature beside, the escapes come first: four Rangers cast
                # it at 1-9 HP beside DL1 Kobolds, a third of the casts
                # failing, and died holding Phase Door (M5d round 4).
                self.pending = DIRS[step]
                return Decision(*magic.pray(MAGIC_MISSILE, f"cast Magic Missile at '{creature.glyph}'"))
            if chebyshev(pos, view.pos) <= 2 and obs.step >= self.level.blind_until \
                    and self.fight_odds(creature, obs) > FIGHT_ODDS and magic.spare(obs, BLIND):
                self.level.blind_until = obs.step + BLIND_TURNS
                self.pending = DIRS[step]
                return Decision(*magic.pray(BLIND, f"pray Blind Creature at '{creature.glyph}'"))
        if obs.step >= self.chant_until and magic.spare(obs, CHANT) and any(
                chebyshev(p, view.pos) <= 3 and self.fight_odds(view.creatures[p], obs) > CHANT_ODDS
                for p in close):
            self.chant_until = obs.step + CHANT_TURNS
            return Decision(*magic.pray(CHANT, "a hard fight coming: pray Chant"))
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
        if self.afraid and magic.can(obs, REMOVE_FEAR):
            return Decision(*magic.pray(REMOVE_FEAR, "afraid: pray Remove Fear"))
        # Sealed in or stuck, not merely "no up stairs seen yet": prayed on
        # arrival, the one try was spent before the level was explored, and
        # a Priest later sealed in there starved for 54,000 steps (M5b round
        # 7). Again every DETECT_EVERY steps. Before healing when nothing is
        # close: starving in a sealed pocket kept HP under half, so the heal
        # always came first and the way out was never looked for (M5b round
        # 8: a Paladin, 34,000 steps on one DL2 level).
        if obs.dlvl and not near and (self.stuck(view) or self.sealed(view)) and obs.step >= self.level.detect_after \
                and magic.can(obs, DETECT_DOORS):
            self.level.detect_after = obs.step + DETECT_EVERY
            return Decision(*magic.pray(DETECT_DOORS, "no way out known: pray Detect Doors/Stairs"))
        if obs.dlvl and not near and self.food_low() and magic.can(obs, CREATE_FOOD):
            # Before a heal: starving drains HP back as fast as Cure Light
            # Wounds restores it, and a Dwarf Priest sealed on DL2 healed
            # 1,166 times while it starved (M5b round 29, seed 1001).
            return Decision(*magic.pray(CREATE_FOOD, "food low: pray Create Food"))
        if obs.hp < PRAY_HEAL_HP * obs.mhp or self.under_spell(obs, view) or self.under_blow(obs, view):
            # Town too: the bot never rests there, and poison kept draining
            # four Priests to death on the walk to the stores (M5b round 3).
            # Only a heal that outruns what the adjacent creatures do back:
            # Cure Light Wounds (3d3) prayed again and again beside a Kobold
            # that took more each turn, until the character died praying
            # (M5b round 8: Priest 1012, Paladin 1006 against a Novice
            # Priest). Fighting on at least hurts the creature.
            hitting = sum(self.incoming(c, obs) for c in self.adjacent)
            for heal in HEALS:
                if magic.can(obs, heal) and (MAGE_HEAL_AVERAGE if magic.mage else HEAL_AVERAGE)[heal] > hitting:
                    return Decision(*magic.pray(heal, f"HP {obs.hp}/{obs.mhp}: pray {heal}"))
        return None

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
                    if c.glyph in knowledge.slow_glyphs() and not self.coins_worth_it(c, obs)}
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
        if view.step_toward(exits(), avoid_monsters=True) is not None:
            return None
        if any(chebyshev(p, view.pos) <= CLEAR_WAY_CALM and not self.stationary(c)
               and c.glyph not in AVOID_GLYPHS for p, c in view.creatures.items()):
            # Not while something else is coming: paralysed beside an eye,
            # the bot was eaten by the Creeping Coins it had walked away from
            # (M4 round 78, seed 1040).
            return None
        bound = STRONG_HP_BASE + STRONG_HP_PER_LEVEL * obs.clvl
        creatures, hazards = view.creatures, view.hazards
        for pos in sorted(creatures, key=lambda p: chebyshev(p, view.pos)):
            creature = creatures[pos]
            if not (self.stationary(creature) or creature.glyph in AVOID_GLYPHS) or \
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
                    {(pos[0] + dx, pos[1] + dy) for dx, dy in DIRS}, avoid_monsters=True)
            finally:
                view.creatures, view.hazards = creatures, hazards
            if not cut:
                continue
            if chebyshev(pos, view.pos) == 1:
                self.last_attack = (pos, creature.glyph)
                return Decision(DIRS[(pos[0] - view.pos[0], pos[1] - view.pos[1])], "fight",
                                f"the '{creature.glyph}' blocks the only way on: attack it")
            return self.move(view, step, "fight", f"the '{creature.glyph}' blocks the only way on: approach it")
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
            step = view.step_toward({(pos[0] + dx, pos[1] + dy) for dx, dy in DIRS}, avoid_monsters=True)
            decision = self.move(view, step, "fight", f"sealed in: approach the '{creature.glyph}' to kill it")
            if decision is not None:
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
                decision = self.move(view, view.step_toward(exits, avoid_monsters=True), "stair-scum",
                                     "level exhausted: path to the nearest staircase")
                if decision is not None:
                    return decision
        if self.food_low():
            # No way up and short of food (M4 round 39: seeds 1002, 1004, 1019,
            # 1020 searched sealed pockets until they starved): down first.
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

    def down_to_climb_back(self, view: View) -> Decision | None:
        if view.type_at(*view.pos) == TYPE_STAIRS_DN:
            return Decision(ord(">"), "stair-scum", "no way up: take the down stairs to climb back")
        return self.move(view, view.step_toward(view.stairs_down(), avoid_monsters=True), "stair-scum",
                         "no way up: path to the down stairs")
