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
from .game import KEY_RUNSTOP, KEY_SPACE, Game, Mode, Observation
from .goals import Goal
from .view import (DIRS, TYPE_DOOR_CLOSED, TYPE_STAIRS_DN, TYPE_STAIRS_UP, TYPE_TRAP, UNKNOWN, Creature, Pos,
                   View, sealed_search_spots)

KEY_BASH = 0x02          # CTRL+B
KEY_REST = ord("5")      # rest one turn. Not CTRL+R: auto-rest ignores hunger (F-M2-1)
KEY_EAT = 0xC5           # SHIFT+E
KEY_SEARCH = ord("S")
KEY_LOOK = ord("X")      # look along a direction; takes no game turn
KEY_WEAR = ord("W")
KEY_REFUEL = 0xD2        # SHIFT+R
KEY_THROW = 0xD4         # SHIFT+T
KEY_DISARM = 0xC4        # SHIFT+D
KEY_RETURN = 0x0D
LOOK_RESULT = re.compile(r"You see an? (.+?)\.")
AVOID_GLYPHS = {"e"}     # Floating Eye: paralysing gaze when meleed
RETREAT_HP = 0.60
RETREAT_RANGE = 12       # farthest staircase worth running for; beyond, fight (round 28)
TRAP_HP = 0.50           # below this share of HP a known trap is impassable (round 20)
BUMP_STEPS = 10          # steps a tile stays blocked after a move into it went nowhere
FIRST_STRIKE_WAITS = 2   # turns to wait for an approaching creature to step into contact
ATTACK_WORDS = ("hits you", "misses you", "bites you", "touches you", "casts")
HUNT_HP = 0.80
OPEN_TRIES, BASH_TRIES = 3, 8
DISARM_TRIES = 3         # disarm attempts on a known trap in the way, then walk over it
SEARCHES_PER_SPOT = 6
SEALED_SEARCHES = 25     # per spot when no exit is reachable: each search only
                         # sometimes finds an adjacent secret door (§14.3 round 7)
SEARCH_BUDGET = 120      # search actions per level before giving up on secret doors
STALL_STEPS = 300        # steps without new map knowledge or XP before stair-scumming
GENERAL_STORE = 0        # store index (entrance "1")
FOODS = ("Ration of Food", "Slime Mold")
FOOD_RESERVE = 2         # below this many known foods, head for town (§14.3 round 3)
RESTOCK_WAIT = 1500      # steps to keep playing after a town visit found no food
RESTOCK_HOPS = 5         # stores restock on every return to town: hops to DL1 and
                         # back before waiting instead (§14.3 round 15)
AFRAID_TURNS = 8         # VMS fresh fear lasts randint(5) + 3 turns (§14.3 round 10)
FOOD_PER_VISIT = 5       # purchases per town visit
LANTERN, OIL, TORCH = "Brass Lantern", "Flask of Oil", "Wooden Torch"
OIL_RESERVE = 3          # flasks to carry: each refills the lantern (§14.3 round 13)
                         # or is thrown when fear blocks melee (round 22)
THROW_RANGE = 5          # farthest in-line creature worth a thrown flask
TORCH_RESERVE = 2        # spare torches to carry when no lantern is for sale
TORCH_TURNS = 4000       # a torch burns ~4,000 turns, a lantern or flask ~7,500: the
LAMP_TURNS = 7500        # screens show no torch charges, so a player keeps rough time
LIGHT_RESERVE = 2000     # turns of light left, with no refill, that send the player to town
REFUEL_AT = 300          # turns of light left at which a flask goes into the lantern
STORE_ITEM = re.compile(r"^\s*([a-l])\) (\S.*?)\s+(\d+) GP")
PACK_ITEM = re.compile(r"^\s*([a-v])\) (\S.*)")


def ready_level(dlvl: int) -> int:
    """Character level a player wants before entering ``dlvl``. Deaths kept
    clustering at the minimum: level n on DL n through round 17, so DL2 needs
    level 3 (round 18); then level 4 on DL3, so DL n >= 3 needs n + 2
    (round 24). DL1 is where a new character starts."""
    if dlvl <= 1:
        return 1
    return dlvl + 1 if dlvl == 2 else dlvl + 2


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
    retreat_path: set[Pos] = field(default_factory=set)   # tiles the current retreat crossed
    retreat_failed: bool = False    # it doubled back: stand and fight until it ends
    bumped: dict[Pos, int] = field(default_factory=dict)   # tile -> step it is blocked until


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
        self.no_food = False                   # "You have no food." until food is bought or picked up
        self.shopped = False                   # done shopping on this town visit
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
        self.light_left -= 1   # rough time: one step, about one turn
        if self.afraid and not fear_news:
            self.afraid -= 1
        attacker = knowledge.attacker(messages)
        self.chased = attacker in knowledge.fast_creatures()
        if self.last_attack is not None and self.last_attack[0] == view.pos:
            # The attack walked onto the tile: nothing was there (round 20).
            self.level.identified[self.last_attack] = ("item", self.last_attack[1])
        self.last_attack = None
        self.identify(view, messages, attacker)
        self.remember_stationary(view)
        view.hazards = set(self.level.stationary)
        self.unseen_attack = not view.creatures and (
            attacker is not None or any(w in messages for w in ATTACK_WORDS))
        self.note_bump(obs, view)
        view.blocked = (self.level.blocked | (set(self.level.stationary) - set(view.creatures))
                        | {p for p, until in self.level.bumped.items() if until > obs.step})
        if obs.hp < TRAP_HP * obs.mhp:
            view.blocked |= view.tiles_of(TYPE_TRAP)   # a trap could kill (round 20)
        decision = self.choose(obs, view)
        if decision.key in DIRS.values() and decision.layer not in ("fight", "look", "prompt"):
            step = next(d for d, k in DIRS.items() if k == decision.key)
            self.last_move = (view.pos, (view.pos[0] + step[0], view.pos[1] + step[1]))
        return decision

    def note_bump(self, obs: Observation, view: View) -> None:
        """A move that left the player in place found something unseen on the
        tile (an invisible creature): keep off it for a while (round 17)."""
        if self.last_move is not None and self.last_move[0] == view.pos:
            self.level.bumped[self.last_move[1]] = obs.step + BUMP_STEPS
        self.last_move = None

    def choose(self, obs: Observation, view: View) -> Decision:
        for layer in (self.retreat, self.look, self.throw, self.fight, self.eat, self.light, self.resupply,
                      self.rest,
                      self.shop, self.descend, self.hunt, self.explore, self.search,
                      self.stair_scum):
            decision = layer(obs, view)
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
        return Decision(ord("5"), "fallback", "nothing to do: rest a turn")

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
            self.end_visit(obs)   # cannot afford it or pack full: stop buying
            return Decision(KEY_SPACE, "shop", "acknowledge the store message")
        self.bought, self.typing = None, []
        if obs.stage == "menu" and not self.shopped:
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
        self.end_visit(obs)
        return Decision(ord("Q"), "shop", f"leave the store ({obs.stage})")

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
        wants: list[str] = list(FOODS) if self.shop_buys < FOOD_PER_VISIT else []
        if not (self.lamp or self.lamp_packed):
            wants.append(LANTERN)
            if self.torches < TORCH_RESERVE:
                wants.append(TORCH)   # only while no lantern is for sale
        elif self.oil < OIL_RESERVE:
            wants.append(OIL)
        return wants

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
            self.food += n
            self.no_food = self.no_food and n < 0
        elif item.startswith(LANTERN):
            self.lamp_packed = n > 0
        elif item.startswith(OIL):
            self.oil += n
        elif item.startswith(TORCH):
            self.torches += n

    def expects_item_prompt(self) -> bool:
        """An item prompt (or its list) is one the brain asked for."""
        return self.picking is not None or self.pending_item is not None

    def pick_item(self, obs: Observation) -> Decision:
        """Answer an item prompt (wear, throw): list the items, then pick by name."""
        for row in obs.rows[1:21]:
            match = PACK_ITEM.match(row)
            if match and match.group(2).startswith(self.picking):
                if self.picking == OIL:
                    self.oil = max(0, self.oil - 1)   # thrown: counted once actually picked
                self.picking = None
                return Decision(ord(match.group(1).upper()), "prompt", f"pick {match.group(2).strip()}")
        if not self.listed and "which item" in obs.rows[0]:
            self.listed = True
            return Decision(ord("?"), "prompt", "list the items")
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
                if chebyshev(pos, view.pos) == 1 and (pos, glyph) not in self.level.identified \
                        and glyph in glyphs and glyph not in seen:
                    self.level.identified[(pos, glyph)] = ("creature", attacker)
        for pos, glyph in list(view.unknown.items()):
            known = self.level.identified.get((pos, glyph))
            if known is not None:
                del view.unknown[pos]
                if known[0] == "creature":
                    view.creatures[pos] = Creature(glyph, names.get(known[1], 0))

    def remember_stationary(self, view: View) -> None:
        """A creature that never moves is still there out of sight (§14.3
        round 15); it is gone once the player stands next to its empty spot."""
        for pos, creature in view.creatures.items():
            if self.stationary(creature):
                self.level.stationary[pos] = creature
        for pos in list(self.level.stationary):
            if pos not in view.creatures and chebyshev(pos, view.pos) <= 1:
                del self.level.stationary[pos]

    def threats(self, view: View) -> set[Pos]:
        """Creatures in view that can reach the player: stationary ones only
        when adjacent."""
        return {p for p, c in view.creatures.items()
                if not self.stationary(c) or chebyshev(p, view.pos) <= 1}

    def track(self, obs: Observation, view: View) -> None:
        if obs.dlvl != self.last_dlvl:
            self.last_dlvl = obs.dlvl
            self.level = LevelMemory()
            self.shopped, self.shop_buys = False, 0
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
        refill = self.oil if self.lamp else self.torches
        return self.light_left < LIGHT_RESERVE and not refill and not self.lamp_packed

    def final_step(self, obs: Observation) -> bool:
        """One more staircase down completes a depth goal (round 12)."""
        return obs.dlvl + 1 == self.goal.target_dlvl and not self.goal.want_xp

    def food_low(self) -> bool:
        return self.no_food or self.food < FOOD_RESERVE

    def count_food(self, messages: str) -> None:
        if "You have no food." in messages:
            self.food = 0
        elif "You eat " in messages:
            self.food = max(0, self.food - 1)
        elif "You picked up" in messages and any(f in messages for f in FOODS):
            self.food += 1

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

    @staticmethod
    def underleveled(obs: Observation) -> bool:
        """Readiness (§14.3 rounds 2, 18): not deeper before ``ready_level``.
        A level-1 character cannot survive one Cause Light Wounds (3d8) from a
        DL2 caster, so a player gains levels before going deeper."""
        return obs.clvl < ready_level(obs.dlvl + 1)

    def engageable(self, creature: Creature, obs: Observation) -> bool:
        return (creature.glyph not in AVOID_GLYPHS and not self.stationary(creature)
                and creature.level <= obs.clvl + 2)

    @staticmethod
    def stationary(creature: Creature) -> bool:
        """Never moves (jellies, molds, …; §14.3 round 9): walk around it,
        never fight it. It only hurts a player who stands next to it."""
        return creature.glyph in knowledge.stationary_glyphs()

    # -- layers ---------------------------------------------------------------------

    def retreat(self, obs: Observation, view: View) -> Decision | None:
        """Escape by stairs (a fresh level loses the creature) when either
        badly hurt with a creature close, or not at full strength with one in view.

        A monster that steps into contact cannot attack that turn, so moving
        toward the stairs costs nothing while it follows. With no stairs known,
        running is pointless: fight on.
        """
        threats = self.threats(view)
        close = self.unseen_attack or any(chebyshev(p, view.pos) <= 2 for p in threats)
        badly_hurt = close and obs.hp < RETREAT_HP * obs.mhp
        if obs.dlvl == 0 or not (threats or self.unseen_attack) or (
                not badly_hurt and obs.hp >= HUNT_HP * obs.mhp and not (self.afraid and close)):
            self.level.retreat_to, self.level.retreat_path = None, set()
            self.level.retreat_failed = False
            return None
        here = view.type_at(*view.pos)
        if here == TYPE_STAIRS_UP:
            return Decision(ord("<"), "retreat", "hurt with a creature close: take the up stairs")
        if here == TYPE_STAIRS_DN and self.deeper_ok(obs):
            return Decision(ord(">"), "retreat", "hurt with a creature close: take the down stairs")
        if ((self.chased and not self.unseen_attack) or self.level.retreat_failed) and not self.afraid:
            # A visible faster attacker, or running did not work: fight
            # (rounds 14, 16). An unseen one cannot be fought: run (round 21).
            return None
        stairs = view.stairs_up() | (view.stairs_down() if self.deeper_ok(obs) else set())
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
            return None
        if not (self.afraid or self.unseen_attack):
            far = view.path_steps({self.level.retreat_to}, avoid_monsters=True, doors=False)
            if far is not None and far > RETREAT_RANGE:
                # Running that far gives a caster or archer free shots: stand
                # and fight what can be fought instead (round 28, seed 1001).
                self.standing = True
                return None
        self.level.retreat_path.add(view.pos)
        if (view.pos[0] + step[0], view.pos[1] + step[1]) in self.level.retreat_path:
            # Doubling back: creatures block every way to the stairs in turn (round 16).
            self.level.retreat_failed = True
            return None
        return Decision(DIRS[step], "retreat", "hurt: run for the nearest stairs")

    def look(self, obs: Observation, view: View) -> Decision | None:
        """Look at the nearest unidentified glyph that is first on one of the
        eight lines from the player (free: no game turn). Once per spot."""
        for pos, glyph in sorted(view.unknown.items(), key=lambda kv: chebyshev(kv[0], view.pos)):
            step = self.line_to(view, pos)
            if step is None or (view.pos, pos) in self.level.looked:
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

    def throw(self, obs: Observation, view: View) -> Decision | None:
        """Fear blocks melee, not throwing: throw a Flask of Oil (2d6) at the
        nearest creature in line (round 22). The lantern keeps one flask."""
        if obs.dlvl == 0 or not self.afraid or self.oil <= (1 if self.lamp else 0):
            return None
        for pos in sorted(self.threats(view), key=lambda p: chebyshev(p, view.pos)):
            step = self.line_to(view, pos)
            if step is None or chebyshev(pos, view.pos) > THROW_RANGE or self.stationary(view.creatures[pos]):
                continue
            self.picking, self.listed, self.pending = OIL, False, DIRS[step]
            return Decision(KEY_THROW, "throw", f"afraid: throw oil at '{view.creatures[pos].glyph}'")
        return None

    def fight(self, obs: Observation, view: View) -> Decision | None:
        if obs.dlvl == 0 or self.afraid:
            return None  # town creatures only fight back when provoked; afraid: cannot melee
        adjacent = sorted((c.level, p) for p, c in view.creatures.items()
                          if chebyshev(p, view.pos) == 1 and c.glyph not in AVOID_GLYPHS
                          and not self.stationary(c))
        if not adjacent:
            return None
        _, (x, y) = adjacent[0]
        self.last_attack = ((x, y), view.creatures[(x, y)].glyph)
        return Decision(DIRS[(x - view.pos[0], y - view.pos[1])], "fight",
                        f"attack adjacent '{view.creatures[(x, y)].glyph}'")

    def rest(self, obs: Observation, view: View) -> Decision | None:
        """Rest one turn at a time to full HP whenever nothing that can reach
        the player is in view."""
        if obs.dlvl == 0 or self.threats(view) or self.unseen_attack or obs.hp >= obs.mhp:
            return None
        return Decision(KEY_REST, "rest", f"HP {obs.hp}/{obs.mhp} and nothing in view")

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
        too_deep = obs.clvl < ready_level(obs.dlvl) - 1
        if obs.dlvl == 0 or not (self.needs_resupply(obs) or too_deep):
            return None
        if self.final_step(obs) and view.stairs_down():
            return None   # finishing the goal beats a trip to town
        why = ("light low" if not self.food_low() else f"{self.food} food left") \
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
        """In town, walk into the General Store once per visit to buy food."""
        if obs.dlvl != 0 or self.shopped or len(view.stores) <= GENERAL_STORE:
            return None
        door = view.stores[GENERAL_STORE]
        step = view.step_toward({door}, avoid_monsters=True) or view.step_toward({door}, avoid_monsters=False)
        return self.move(view, step, "shop", "walk to the General Store for food")

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
        return self.move(view, step, "explore", "path to the nearest unexplored edge")

    @staticmethod
    def sealed(view: View) -> bool:
        """No stairs and no unexplored edge are reachable: only a secret door
        can let the player out."""
        exits = view.frontier() | view.stairs_up() | view.stairs_down()
        return view.step_toward(exits, avoid_monsters=False) is None

    def search(self, obs: Observation, view: View, *, forced: bool = False,
               per_spot: int = SEARCHES_PER_SPOT) -> Decision | None:
        """Secret doors only matter when the goal needs somewhere unreached (depth),
        or when the level has no known exit at all (``forced``). Never while
        something unseen attacks: searching stands still (round 21)."""
        if self.unseen_attack:
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
        per_spot = SEALED_SEARCHES if self.sealed(view) else SEARCHES_PER_SPOT
        decision = self.search(obs, view, forced=True, per_spot=per_spot)
        if decision is not None or obs.dlvl >= self.goal.target_dlvl:
            return decision
        # No way up and nothing left to search (§14.3 round 4): go down even if
        # not ready, then climb straight back to a fresh level (``resupply``).
        if here == TYPE_STAIRS_DN:
            return Decision(ord(">"), "stair-scum", "no way up: take the down stairs to climb back")
        return self.move(view, view.step_toward(view.stairs_down(), avoid_monsters=True), "stair-scum",
                         "no way up: path to the down stairs")
