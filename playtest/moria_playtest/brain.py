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
from .game import ITEM_PROMPT, KEY_RUNSTOP, KEY_SPACE, Game, Mode, Observation
from .goals import Goal
from .view import (DIRS, TYPE_DOOR_CLOSED, TYPE_STAIRS_DN, TYPE_STAIRS_UP, TYPE_TRAP, UNKNOWN, Creature, Pos,
                   View, sealed_search_spots)

KEY_BASH = 0x02          # CTRL+B
KEY_REST = ord("5")      # rest one turn (waiting for a first strike)
KEY_AUTOREST = 0x12      # CTRL+R: rest until recovered or disturbed (TRN-007); heals at
                         # the doubled VMS resting rate (TRN-009)
KEY_EAT = 0xC5           # SHIFT+E
KEY_SEARCH = ord("S")
KEY_LOOK = ord("X")      # look along a direction; takes no game turn
KEY_WEAR = ord("W")
KEY_REFUEL = 0xD2        # SHIFT+R
KEY_THROW = 0xD4         # SHIFT+T
KEY_DISARM = 0xC4        # SHIFT+D
KEY_PICKUP = ord("G")
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
STARTING_WEAPON = ("Dagger", 0)               # core/game_loop.s starting equipment: (name, to-dam)
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
CLW_GOLD = 60            # gold worth a Temple trip for Cure Light Wounds (base 50 gp)
RECALL_GOLD = 250        # ... for Word of Recall (base 200 gp; M4 round 45: round 44's
                         # trips without the gold cost ~6,700 steps for 2 scrolls)
STATUS_GOLD = re.compile(r"AU:\s*(\d+)")
CLW = "Potion of Cure Light"   # Cure Light Wounds (the store line may cut the name short)
CLW_RESERVE = 5          # potions to carry for a fight gone wrong (M4; 3 until round 56, when
                         # most deaths came after drinking all three and gold was plentiful)
QUAFF_HP = 0.3           # below this fraction of max HP, drink one
FOODS = ("Ration of Food", "Slime Mold")
SLIME = 1 / 3            # a Slime Mold feeds 500 turns, a Ration 1,500 (core/player_items.s)
FOOD_PER_DEPTH = 3       # one more ration of reserve per this many levels down (M4 round 42)
FOOD_RESERVE = 2         # below this many known foods, head for town (§14.3 round 3)
FOOD_MAX = 20            # rations' worth to carry at most (10 until M4 round 80: items stack
                         # now, so food no longer fills the pack; maintainer: "carry more food")
RESTOCK_WAIT = 1500      # steps to keep playing after a town visit found no food
RESTOCK_HOPS = 5         # stores restock on every return to town: hops to DL1 and
                         # back before waiting instead (§14.3 round 15)
AFRAID_TURNS = 8         # VMS fresh fear lasts randint(5) + 3 turns (§14.3 round 10)
FOOD_PER_VISIT = 16      # food purchases per town visit (5 until M4 round 42, 8 until round 80)
LANTERN, OIL, TORCH = "Brass Lantern", "Flask of Oil", "Wooden Torch"
OIL_RESERVE = 3          # flasks to carry: each refills the lantern (§14.3 round 13)
                         # or is thrown when fear blocks melee (round 22)
THROW_RANGE = 5          # farthest in-line creature worth a thrown flask
TORCH_RESERVE = 2        # spare torches to carry: the light, or the lantern's backup (M4)
TORCH_TURNS = 4000       # a torch burns ~4,000 turns, a lantern or flask ~7,500: the
LAMP_TURNS = 7500        # screens show no torch charges, so a player keeps rough time
LIGHT_RESERVE = 2000     # turns of light left, with no refill, that send the player to town
REFUEL_AT = 300          # turns of light left at which a flask goes into the lantern
STORE_ITEM = re.compile(r"^\s*([a-l])\) (\S.*?)\s+(\d+) GP")
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
        self.armour = dict(STARTING_ARMOUR)    # armour slot -> AC worn or bought to wear
        self.to_wear: list[str] = []           # bought, not yet worn or wielded
        self.gear: dict[str, tuple[str, object]] = {}   # store name -> what buying it changes
        self.recall = 0                        # Word of Recall scrolls carried
        self.recalling = False                 # read one; the yank comes in 15-29 turns
        self.max_dlvl = 0                      # deepest level reached (where recall returns)
        self.trip_dlvl = 0                     # deepest level since the last time in town
        self.at_store: int | None = None       # store the last walk into town led to
        self.clw = 0                           # Cure Light Wounds potions carried
        self.shop_buys = 0                     # purchases started on this town visit
        self.store_letter: str | None = None   # item letter for the next "Buy which item?"
        self.pending_look: tuple[Pos, str] | None = None   # glyph the last look aimed at
        self.food = 1                          # foods carried, as a player counts them:
                                               # starting kit 1, +bought/picked up, -eaten
        self.buying: str | None = None         # store item named by the last B)uy
        self.bought: str | None = None         # purchase counted, undone if the store objects
        self.typing: list[int] = []            # haggle offer keys still to type
        self.lamp = False                      # wearing a Brass Lantern
        self.lamp_packed = False               # bought a lantern, not yet worn
        self.oil = 0                           # flasks of oil carried
        self.torches = 0                       # spare torches carried
        self.light_left = TORCH_TURNS          # estimated turns of light (steps overcount)
        self.dark = False                      # the light has gone out
        self.picking: str | None = None        # item to pick at the next item prompt (wear, throw)
        self.listed = False                    # the wear prompt's item list is showing
        self.resupply_after = 0                # step before which town is not worth a trip
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
        self.noted_messages, self.noted_on_prompt = messages, obs.mode != Mode.COMMAND
        if obs.mode != Mode.COMMAND:
            return self.prompt(obs)
        assert view is not None
        self.pending = self.pending_item = self.picking = None   # their prompts are past
        self.standing = False
        self.track(obs, view)
        self.remember_tiles(view)
        self.light_left -= 1   # rough time: one step, about one turn
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
        for layer in (self.swat, self.quaff, self.throw, self.crowded, self.retreat, self.look, self.fight, self.eat,
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
            race, klass = self.goal.character
            return Decision(Game.chargen_key(obs, self.name, race, klass), "prompt", f"chargen {obs.stage}")
        if self.picking is not None and obs.mode == Mode.ITEM:
            return self.pick_item(obs)   # a -more- first keeps the pick pending
        if obs.mode == Mode.DISMISS:
            return Decision(KEY_SPACE, "prompt", f"dismiss {obs.stage}")
        if obs.mode == Mode.DEATH:
            return Decision(KEY_SPACE, "prompt", "death flow")
        if obs.mode == Mode.STORE:
            return self.store(obs)
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
            if self.bought is not None:
                self.credit(self.bought, -1)   # the counted purchase did not happen
            self.bought = None
            self.leave_store(obs)   # cannot afford it or pack full: stop buying
            return Decision(KEY_SPACE, "shop", "acknowledge the store message")
        self.bought, self.typing = None, []
        done = {TEMPLE: self.potions_done, BLACK_MARKET: self.market_done, ARMOURY: self.armoury_done,
                WEAPONSMITH: self.weapons_done, ALCHEMIST: self.alchemist_done}.get(self.at_store, self.shopped)
        if obs.stage == "menu" and not done and self.at_store in (ARMOURY, WEAPONSMITH):
            pick = self.gear_pick(obs)
            if pick is not None:
                self.store_letter, self.buying = pick
                return Decision(ord("B"), "shop", f"buy {pick[1]}")
        elif obs.stage == "menu" and not done:
            gold = re.search(r"Gold: (\d+)", obs.rows[16])
            for want in self.shopping_list():
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

    def shopping_list(self) -> list[str]:
        """Store items worth buying now, most important first."""
        wants: list[str] = []
        if self.shop_buys < FOOD_PER_VISIT and self.food < FOOD_MAX:
            # A Slime Mold is a third of a ration in a whole slot: only near
            # the reserve (M4 round 57: rations only once the reserve was
            # made bought nothing when the store had none, and 8 starved).
            wants = list(FOODS) if self.food < self.food_reserve() + 2 else [FOODS[0]]
        if not (self.lamp or self.lamp_packed):
            wants.append(LANTERN)
        if self.torches < TORCH_RESERVE:
            wants.append(TORCH)   # backup light (M4: seed 1007 played 3,400 steps in the dark)
        if self.oil < OIL_RESERVE:
            wants.append(OIL)   # lantern fuel, and a missile fear cannot stop (M4: Poltergeist)
        if self.clw < CLW_RESERVE:
            wants.append(CLW)
        if self.recall < RECALL_RESERVE:
            wants.append(RECALL)
        if self.at_store in (BLACK_MARKET, ALCHEMIST):
            wants = [w for w in wants if w == RECALL]   # nothing else is wanted there
        return wants

    def stats(self, obs: Observation) -> tuple[int, int]:
        """Strength and dexterity from the status lines (18/xx as 18 + xx/10)."""
        found = {}
        for row in obs.rows[19:24]:
            for name, base, extra in STAT.findall(row):
                found[name] = int(base) + (10 if extra == "**" else int(extra) // 10 if extra else 0)
        return found.get("ST", 10), found.get("DX", 10)

    def melee_score(self, name: str, to_dam: int, obs: Observation) -> float:
        """Expected melee damage a turn before to-hit: blows (Umoria's table,
        ``combat_calc_blows``) times the dice average plus the to-dam bonus."""
        kind = knowledge.item_kinds().get(name)
        if kind is None or not kind.melee:
            return 0.0
        strength, dexterity = self.stats(obs)
        return knowledge.blows(strength, dexterity, kind.weight) * (kind.dice * (kind.sides + 1) / 2 + to_dam)

    def gear_pick(self, obs: Observation) -> tuple[str, str] | None:
        """At the Armoury or Weaponsmith: the item that most improves what is
        worn in its slot, or the weapon wielded, that the gold allows while
        keeping ``GEAR_RESERVE`` (M4 round 74: characters met Green Nagas on
        DL5-9 with the starting Dagger and AC 4, carrying thousands of gold)."""
        gold = re.search(r"Gold: (\d+)", obs.rows[16])
        budget = (int(gold.group(1)) if gold else 0) - GEAR_RESERVE
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
                gain, change = ac - self.armour.get(kind.category, 0), ("armour", (kind.category, ac))
            else:
                weapon = GEAR_WEAPON.match(name)
                to_dam = int(weapon.group(3)) if weapon and weapon.group(3) else 0
                base = weapon.group(1) if weapon else name
                gain = self.melee_score(base, to_dam, obs) - self.melee_score(*self.weapon, obs)
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
        elif item in self.gear and n > 0:
            self.to_wear.append(item)
        elif item in self.gear and item in self.to_wear:
            self.to_wear.remove(item)   # the counted purchase did not happen

    def expects_item_prompt(self) -> bool:
        """An item prompt (or its list) is one the brain asked for."""
        return self.picking is not None or self.pending_item is not None

    def pick_item(self, obs: Observation) -> Decision:
        """Answer an item prompt (wear, throw): list the items, then pick by name."""
        for row in obs.rows[1:]:   # a full pack lists a-v down to row 22 (M4: item u was missed)
            match = PACK_ITEM.match(row)
            if match and match.group(2).startswith(self.picking):
                if self.picking == OIL:
                    self.oil = max(0, self.oil - 1)   # thrown: counted once actually picked
                elif self.picking == CLW:
                    self.clw = max(0, self.clw - 1)
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
                if chebyshev(pos, view.pos) == 1 and (known is None or known[0] == "item") \
                        and glyph in glyphs and glyph not in seen:
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
        self.trail = (self.trail + [view.pos])[-OSCILLATION_STEPS:]
        if decision.key not in DIRS.values() or decision.layer in ("fight", "look", "prompt"):
            return decision
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
        visit that found the store without it)."""
        return self.supplies_low() and obs.step >= self.resupply_after

    def supplies_low(self) -> bool:
        return self.food_low() or self.light_low()

    def light_low(self) -> bool:
        refill = (self.oil if self.lamp else 0) + self.torches
        return self.light_left < LIGHT_RESERVE and not refill and not self.lamp_packed

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
        if "You are wearing a Brass Lantern" in messages:
            self.torches += not (self.lamp or self.dark)   # the lit torch went into the pack
            self.lamp, self.light_left, self.dark = True, LAMP_TURNS, False
        elif "You are wearing a Wooden Torch" in messages:
            self.lamp, self.light_left, self.dark = False, TORCH_TURNS, False
            self.torches = max(0, self.torches - 1)
        if "Your light has gone out." in messages:
            self.lamp, self.light_left, self.dark = False, 0, True
        if "Your lamp is refueled." in messages or "Your lamp overflows." in messages:
            self.light_left = LAMP_TURNS
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
        DL2 caster, so a player gains levels before going deeper."""
        return obs.clvl < ready_level(obs.dlvl + 1, self.goal.ready_margin)

    def too_strong(self, creature: Creature, obs: Observation) -> bool:
        """Monster lore, before any fight: far more HP or armour than the
        character can wear down at its level (M4 rounds 52-62: nagas, orcs,
        skeleton orcs and coins killed most characters that fought them).
        Only for goals that hunt for experience: a diving character is
        outmatched nearly everywhere, and running from all of it halved
        reach_dl10 (M4 round 64 A/B: 13 of 40 against 22 of 40)."""
        return self.goal.want_xp and self.lore_strong(creature, obs)

    @staticmethod
    def lore_strong(creature: Creature, obs: Observation) -> bool:
        hp, ac = knowledge.strength().get((creature.glyph, creature.level), (0.0, 0))
        return (hp > STRONG_HP_BASE + STRONG_HP_PER_LEVEL * obs.clvl
                or ac > STRONG_AC_BASE + STRONG_AC_PER_LEVEL * obs.clvl)

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
                and creature.level <= obs.clvl + 2)

    @staticmethod
    def coins_worth_it(creature: Creature, obs: Observation) -> bool:
        """Never: Creeping Coins drop their gold when killed (MON-014), but
        their poison touch killed 6 a round even fought at full strength (M4
        round 58), and other drops pay for supplies now. Kept as the one
        place to change that policy."""
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

    def retreat(self, obs: Observation, view: View) -> Decision | None:
        """Escape by stairs (a fresh level loses the creature) when either
        badly hurt with a creature close, or not at full strength with one in view.

        A monster that steps into contact cannot attack that turn, so moving
        toward the stairs costs nothing while it follows. With no stairs known,
        running is pointless: fight on.
        """
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
            return self.walk_away(view, threats)
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
        if len(close) < CROWD_COUNT:
            return None
        key = ord("<") if here == TYPE_STAIRS_UP else ord(">")
        return Decision(key, "retreat", f"{len(close)} creatures close: take the stairs")

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
        a fast attacker follows a runner."""
        if obs.dlvl == 0 or not self.afraid or self.oil <= (1 if self.lamp and not self.torches else 0):
            return None
        for pos in sorted(self.threats(view), key=lambda p: chebyshev(p, view.pos)):
            step = self.line_to(view, pos)
            if step is None or chebyshev(pos, view.pos) > THROW_RANGE or self.stationary(view.creatures[pos]):
                continue
            self.picking, self.listed, self.pending = OIL, False, DIRS[step]
            return Decision(KEY_THROW, "throw", f"afraid: throw oil at '{view.creatures[pos].glyph}'")
        return None

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
        if all(view.creatures[p].glyph in knowledge.slow_glyphs()
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
                  if p not in self.level.collected and (glyph == COIN_GLYPH or name.startswith(FOODS))
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
        if obs.dlvl == 0 or not (self.needs_resupply(obs) or too_deep):
            return None
        if self.final_step(obs) and (view.stairs_down() or not (
                self.no_food or self.food < FOOD_RESERVE or self.light_low())):
            # Finishing the goal beats a trip to town. The depth-scaled
            # reserve is for the climb home: one level from the goal, it sent
            # seed 1026 back up from DL9 with 4 rations, into a sealed DL8
            # pocket where it starved (M4 round 70).
            return None
        why = ("light low" if not self.food_low() else f"{self.food:.3g} food left") \
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

    def shop(self, obs: Observation, view: View) -> Decision | None:
        """In town, walk into the General Store once per visit to buy food,
        then the Alchemist for Cure Light Wounds while short of them (M4)."""
        if obs.dlvl != 0:
            return None
        if not self.shopped and len(view.stores) > GENERAL_STORE:
            store, why = GENERAL_STORE, "walk to the General Store for food"
        elif not self.alchemist_done and len(view.stores) > ALCHEMIST and self.recall < RECALL_RESERVE \
                and self.gold(obs) >= RECALL_GOLD:
            # Word of Recall before potions: Cure Light Wounds bought first
            # left too little gold for it, and characters with none starved
            # stuck (M4 round 91: seeds 1003, 1006, 1016).
            store, why = ALCHEMIST, "walk to the Alchemy shop for Word of Recall"
        elif not self.potions_done and len(view.stores) > TEMPLE and self.temple_worth_it(obs):
            store, why = TEMPLE, "walk to the Temple for Cure Light Wounds and Word of Recall"
        elif not self.market_done and len(view.stores) > BLACK_MARKET and self.market_worth_it(obs):
            store, why = BLACK_MARKET, "walk to the Black Market for Word of Recall"
        elif not self.weapons_done and len(view.stores) > WEAPONSMITH and self.gold(obs) > GEAR_RESERVE:
            store, why = WEAPONSMITH, "walk to the Weaponsmith for a better weapon"
        elif not self.armoury_done and len(view.stores) > ARMOURY and self.gold(obs) > GEAR_RESERVE:
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
            spare = self.gold(obs) > GEAR_RESERVE
            ready = self.shopped and (self.potions_done or len(view.stores) <= TEMPLE) and (
                self.alchemist_done or self.recall >= RECALL_RESERVE or self.gold(obs) < RECALL_GOLD) and (
                self.market_done or not self.market_worth_it(obs)) and not self.to_wear and (
                self.weapons_done or not spare) and (self.armoury_done or not spare)
            if not ready or self.max_dlvl < RECALL_FROM or self.supplies_low():
                return None
        elif not (self.food_low() and self.sealed(view)) and not self.stuck(view) and (
                obs.dlvl < RECALL_FROM or not self.needs_resupply(obs)):
            # Sealed in and short of food, any depth: the only other way out
            # is a secret door the searches have not found (M4 round 53: 4
            # of 11 reach_dl10 deaths starved searching).
            return None
        self.picking, self.listed = RECALL, False
        return Decision(ord("R"), "recall", "read Word of Recall")

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
        return self.recall < RECALL_RESERVE and match is not None and int(match.group(1)) >= MARKET_GOLD

    def temple_worth_it(self, obs: Observation) -> bool:
        """A Temple trip only with the gold for what is wanted there."""
        match = STATUS_GOLD.search(obs.rows[23])
        gold = int(match.group(1)) if match else 0
        return (self.clw < CLW_RESERVE and gold >= CLW_GOLD) or \
            (self.recall < RECALL_RESERVE and gold >= RECALL_GOLD)

    def quaff(self, obs: Observation, view: View) -> Decision | None:
        """Badly hurt with a Cure Light Wounds potion: drink it (M4)."""
        if obs.dlvl == 0 or not self.clw or obs.hp >= QUAFF_HP * obs.mhp:
            return None
        self.picking, self.listed = CLW, False
        return Decision(ord("Q"), "quaff", f"HP {obs.hp}/{obs.mhp}: drink Cure Light Wounds")

    def descend(self, obs: Observation, view: View) -> Decision | None:
        if not self.deeper_ok(obs):
            return None
        if view.type_at(*view.pos) == TYPE_STAIRS_DN:
            return Decision(ord(">"), "descend", "on a down staircase")
        stairs = view.stairs_down()
        if not stairs:
            return None
        step = view.step_toward(stairs, avoid_monsters=True) or view.step_toward(stairs, avoid_monsters=False)
        return self.move(view, step, "descend", "path to known down staircase")

    def hunt(self, obs: Observation, view: View) -> Decision | None:
        if obs.dlvl == 0 or self.afraid or not (self.goal.want_xp or self.underleveled(obs) or self.standing):
            return None
        targets = {p for p, c in view.creatures.items() if self.engageable(c, obs)}
        if not targets or (obs.hp < HUNT_HP * obs.mhp and not self.standing):
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
        if here == TYPE_STAIRS_UP or (here == TYPE_STAIRS_DN and deeper_ok):
            return Decision(ord("<") if here == TYPE_STAIRS_UP else ord(">"), "stair-scum",
                            "level exhausted: take the stairs to a fresh level")
        exits = view.stairs_up() | (view.stairs_down() if deeper_ok else set())
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
