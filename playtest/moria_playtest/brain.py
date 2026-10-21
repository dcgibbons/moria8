"""Brain v1 (§6.6): deterministic, explainable, only what the current goals need.

Layers, first match wins: prompt (and store) -> retreat -> fight -> eat -> rest
-> shop -> descend -> hunt -> explore -> search -> stair-scum. Every decision records (layer,
reason, key). The brain reads only the fair-play ``View`` and the
observation's mode, stage, status line, HP and depth.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

from .game import KEY_RUNSTOP, KEY_SPACE, Game, Mode, Observation
from .goals import Goal
from .view import DIRS, TYPE_DOOR_CLOSED, TYPE_STAIRS_DN, TYPE_STAIRS_UP, UNKNOWN, Creature, Pos, View

KEY_BASH = 0x02          # CTRL+B
KEY_REST = ord("5")      # rest one turn. Not CTRL+R: auto-rest ignores hunger (F-M2-1)
KEY_EAT = 0xC5           # SHIFT+E
KEY_SEARCH = ord("S")
AVOID_GLYPHS = {"e"}     # Floating Eye: paralysing gaze when meleed
RETREAT_HP = 0.60
FIRST_STRIKE_WAITS = 2   # turns to wait for an approaching creature to step into contact
ATTACK_WORDS = ("hits you", "misses you", "bites you", "touches you", "casts")
HUNT_HP = 0.80
OPEN_TRIES, BASH_TRIES = 3, 8
SEARCHES_PER_SPOT = 6
SEARCH_BUDGET = 120      # search actions per level before giving up on secret doors
STALL_STEPS = 300        # steps without new map knowledge or XP before stair-scumming
GENERAL_STORE = 0        # store index (entrance "1")
FOODS = ("Ration of Food",)
FOOD_PER_VISIT = 5       # purchases per town visit
STORE_ITEM = re.compile(r"^\s*([a-l])\) (\S.*)")


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
    blocked: set[Pos] = field(default_factory=set)
    searches: dict[Pos, int] = field(default_factory=dict)
    known: int = 0
    since_progress: int = 0
    scum: bool = False
    stall_reported: bool = False


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
        self.events: list[str] = []            # bot-quality events for the session (stalls)

    def state(self) -> dict[str, object]:
        """JSON-serializable state saved beside snapshots."""
        return {"last_dlvl": self.last_dlvl, "last_xp": self.last_xp,
                "scum": self.level.scum, "since_progress": self.level.since_progress}

    def decide(self, obs: Observation, view: View | None) -> Decision:
        if obs.mode != Mode.COMMAND:
            return self.prompt(obs)
        assert view is not None
        self.pending = self.pending_item = None
        self.track(obs, view)
        messages = obs.rows[0] + obs.rows[1]
        self.unseen_attack = not view.creatures and any(w in messages for w in ATTACK_WORDS)
        view.blocked = self.level.blocked
        for layer in (self.retreat, self.fight, self.eat, self.rest, self.shop, self.descend,
                      self.hunt, self.explore, self.search, self.stair_scum):
            decision = layer(obs, view)
            if decision is not None:
                return decision
        return Decision(ord("5"), "fallback", "nothing to do: rest a turn")

    # -- prompt layer -------------------------------------------------------------

    def prompt(self, obs: Observation) -> Decision:
        if obs.mode == Mode.CHARGEN:
            race, klass = self.goal.character
            return Decision(Game.chargen_key(obs, self.name, race, klass), "prompt", f"chargen {obs.stage}")
        if obs.mode == Mode.DISMISS:
            return Decision(KEY_SPACE, "prompt", f"dismiss {obs.stage}")
        if obs.mode == Mode.DEATH:
            return Decision(KEY_SPACE, "prompt", "death flow")
        if obs.mode == Mode.STORE:
            return self.store(obs)
        if obs.mode == Mode.DIRECTION and self.pending is not None:
            key, self.pending = self.pending, None
            return Decision(key, "prompt", "direction for the pending door action")
        if self.pending_item is not None and "which" in obs.rows[0]:
            key, self.pending_item = self.pending_item, None
            return Decision(key, "prompt", "first matching item")
        return Decision(KEY_RUNSTOP, "prompt", f"cancel unknown prompt {obs.stage}".strip())

    def store(self, obs: Observation) -> Decision:
        """Buy food at the General Store; never haggle (food is a 10 gp-or-less Y/N buy)."""
        if obs.stage == "buy_which" and self.store_letter is not None:
            letter, self.store_letter = self.store_letter, None
            return Decision(ord(letter.upper()), "shop", f"buy item {letter}")
        if obs.stage == "buy_confirm":
            self.no_food = False
            return Decision(ord("Y"), "shop", "confirm the price")
        if obs.stage == "message":
            self.shopped = True   # cannot afford it or pack full: stop buying
            return Decision(KEY_SPACE, "shop", "acknowledge the store message")
        if obs.stage == "menu" and not self.shopped and self.shop_buys < FOOD_PER_VISIT:
            for row in obs.rows[3:15]:
                match = STORE_ITEM.match(row)
                if match and match.group(2).startswith(FOODS):
                    self.store_letter = match.group(1)
                    self.shop_buys += 1
                    return Decision(ord("B"), "shop", f"buy {match.group(2).split('  ')[0]}")
        self.shopped = True
        return Decision(ord("Q"), "shop", f"leave the store ({obs.stage})")

    # -- bookkeeping ----------------------------------------------------------------

    def track(self, obs: Observation, view: View) -> None:
        if obs.dlvl != self.last_dlvl:
            self.last_dlvl = obs.dlvl
            self.level = LevelMemory()
            self.shopped, self.shop_buys = False, 0
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
        """Turn a path step into a key; doors on the path are opened or bashed first."""
        if step is None or step == (0, 0):
            return None
        target = (view.pos[0] + step[0], view.pos[1] + step[1])
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

    def engageable(self, creature: Creature, obs: Observation) -> bool:
        return creature.glyph not in AVOID_GLYPHS and creature.level <= obs.clvl + 2

    # -- layers ---------------------------------------------------------------------

    def retreat(self, obs: Observation, view: View) -> Decision | None:
        """Escape by stairs (a fresh level loses the creature) when either
        badly hurt with a creature close, or not at full strength with one in view.

        A monster that steps into contact cannot attack that turn, so moving
        toward the stairs costs nothing while it follows. With no stairs known,
        running is pointless: fight on.
        """
        if obs.dlvl == 0 or not (view.creatures or self.unseen_attack):
            return None
        close = self.unseen_attack or any(chebyshev(p, view.pos) <= 2 for p in view.creatures)
        badly_hurt = close and obs.hp < RETREAT_HP * obs.mhp
        if not badly_hurt and obs.hp >= HUNT_HP * obs.mhp:
            return None
        here = view.type_at(*view.pos)
        if here == TYPE_STAIRS_UP:
            return Decision(ord("<"), "retreat", "hurt with a creature close: take the up stairs")
        if here == TYPE_STAIRS_DN and obs.dlvl < self.goal.target_dlvl:
            return Decision(ord(">"), "retreat", "hurt with a creature close: take the down stairs")
        stairs = view.stairs_up() | (view.stairs_down() if obs.dlvl < self.goal.target_dlvl else set())
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
        return Decision(DIRS[step], "retreat", "hurt: run for the nearest stairs")

    def fight(self, obs: Observation, view: View) -> Decision | None:
        if obs.dlvl == 0:
            return None  # town creatures only fight back when provoked
        adjacent = sorted((c.level, p) for p, c in view.creatures.items()
                          if chebyshev(p, view.pos) == 1 and c.glyph not in AVOID_GLYPHS)
        if not adjacent:
            return None
        _, (x, y) = adjacent[0]
        return Decision(DIRS[(x - view.pos[0], y - view.pos[1])], "fight",
                        f"attack adjacent '{view.creatures[(x, y)].glyph}'")

    def rest(self, obs: Observation, view: View) -> Decision | None:
        """Rest one turn at a time to full HP whenever nothing is in view."""
        if obs.dlvl == 0 or view.creatures or self.unseen_attack or obs.hp >= obs.mhp:
            return None
        return Decision(KEY_REST, "rest", f"HP {obs.hp}/{obs.mhp} and nothing in view")

    def eat(self, obs: Observation, view: View) -> Decision | None:
        """Eat when hungry. Eating with no food takes no game time, so retrying
        it would loop forever: go up toward town to buy more instead."""
        messages = obs.rows[0] + obs.rows[1]
        if "You have no food." in messages:
            self.no_food = True
        elif "You picked up" in messages:
            self.no_food = False
        status = obs.rows[23]
        if not any(word in status for word in ("Hungry", "Weak", "Faint")):
            return None
        if not self.no_food:
            self.pending_item = ord("A")
            return Decision(KEY_EAT, "eat", "hungry: eat the first food item")
        if obs.dlvl == 0:
            return None
        if view.type_at(*view.pos) == TYPE_STAIRS_UP:
            return Decision(ord("<"), "eat", "out of food: go up toward town")
        return self.move(view, view.step_toward(view.stairs_up(), avoid_monsters=True), "eat",
                         "out of food: path to the up stairs")

    def shop(self, obs: Observation, view: View) -> Decision | None:
        """In town, walk into the General Store once per visit to buy food."""
        if obs.dlvl != 0 or self.shopped or len(view.stores) <= GENERAL_STORE:
            return None
        door = view.stores[GENERAL_STORE]
        step = view.step_toward({door}, avoid_monsters=True) or view.step_toward({door}, avoid_monsters=False)
        return self.move(view, step, "shop", "walk to the General Store for food")

    def descend(self, obs: Observation, view: View) -> Decision | None:
        if obs.dlvl >= self.goal.target_dlvl:
            return None
        if view.type_at(*view.pos) == TYPE_STAIRS_DN:
            return Decision(ord(">"), "descend", "on a down staircase")
        stairs = view.stairs_down()
        if not stairs:
            return None
        step = view.step_toward(stairs, avoid_monsters=True) or view.step_toward(stairs, avoid_monsters=False)
        return self.move(view, step, "descend", "path to known down staircase")

    def hunt(self, obs: Observation, view: View) -> Decision | None:
        if not self.goal.want_xp or obs.dlvl == 0:
            return None
        targets = {p for p, c in view.creatures.items() if self.engageable(c, obs)}
        if not targets or obs.hp < HUNT_HP * obs.mhp:
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
        if self.level.scum or obs.dlvl == 0:
            return None
        frontier = view.frontier()
        step = view.step_toward(frontier, avoid_monsters=True) if frontier else None
        if step is None:   # the only way on is across a known trap
            step = view.step_toward(view.frontier(traps=True), avoid_monsters=True)
        return self.move(view, step, "explore", "path to the nearest unexplored edge")

    def search(self, obs: Observation, view: View, *, forced: bool = False) -> Decision | None:
        """Secret doors only matter when the goal needs somewhere unreached (depth),
        or when the level has no known exit at all (``forced``)."""
        if not forced:
            if self.level.scum or obs.dlvl == 0 or obs.dlvl >= self.goal.target_dlvl:
                return None
            if sum(self.level.searches.values()) >= SEARCH_BUDGET:
                self.level.scum = True
                return None
        searched = {p for p, n in self.level.searches.items() if n >= SEARCHES_PER_SPOT}
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
        deeper_ok = obs.dlvl < self.goal.target_dlvl
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
        return self.search(obs, view, forced=True)
