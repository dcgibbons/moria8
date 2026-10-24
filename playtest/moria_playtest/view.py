"""Fair-play view (§6.5): what a player could know, and nothing more.

- Map: read from memory but gated by ``FLAG_VISITED``; secret doors read as
  wall; unvisited tiles are unknown. (Unfound traps are plain floor in memory.)
- Creatures: whatever creature glyphs the *screen* shows in the viewport. The
  monster table is consulted only to identify a glyph already on screen
  (creature level), as a player would by looking at it.
- Unknown glyphs: other non-terrain symbols (`$`, `,`, `!`, …) may be items or
  creatures; the brain identifies them with the look command (§14.3), using
  player knowledge of creature names from ``knowledge`` (§6.5).
- Town: the store entrances (a fixed layout every player knows).
The brain sees only this view. Privileged state stays with the auditor.
"""

from __future__ import annotations

import heapq
from functools import lru_cache
from dataclasses import dataclass, field

from .game import Game, Observation

UNKNOWN = -1
WALL = 0x1   # TILE_WALL_H type nibble; stands in for every blocking type
WALKABLE_TYPES = {0x0, 0x7, 0x9, 0xA, 0xB, 0xE}   # walkable_table, core/player_move.s
TYPE_DOOR_OPEN, TYPE_DOOR_CLOSED = 0x7, 0x8
TYPE_STAIRS_DN, TYPE_STAIRS_UP, TYPE_RUBBLE, TYPE_TRAP, TYPE_SECRET = 0x9, 0xA, 0xB, 0xE, 0xF

DIRS = {(0, -1): ord("K"), (0, 1): ord("J"), (-1, 0): ord("H"), (1, 0): ord("L"),
        (-1, -1): ord("Y"), (1, -1): ord("U"), (-1, 1): ord("B"), (1, 1): ord("N")}

Pos = tuple[int, int]
TRAP_COST = 25   # extra steps a path will walk to go around a known trap
UNKNOWN_COST = TRAP_COST   # ... or past an unidentified glyph (twice that onto one)
HAZARD_COST = 150   # ... or past a hazard: a Yellow Jelly's poison touch stacked on every
                    # pass of a corridor beside it (M4 round 48, seed 1009)
# Screen characters that are terrain, not things (core/color.s tile_screen_codes;
# the trap/rune glyph decodes as '·'; town store entrances are digits).
TERRAIN_GLYPHS = set(".#'+><:%· ") | set("12345678")


def is_unknown_glyph(char: str) -> bool:
    """A screen symbol that could be an item or a creature: not terrain,
    not a letter (always a creature) and not the player."""
    return not char.isalpha() and char != "@" and char not in TERRAIN_GLYPHS


@dataclass(frozen=True)
class Creature:
    glyph: str
    level: int


@dataclass
class View:
    cols: int
    rows: int
    types: list[int]                  # tile type nibble, or UNKNOWN
    pos: Pos
    dlvl: int
    creatures: dict[Pos, Creature] = field(default_factory=dict)
    blocked: set[Pos] = field(default_factory=set)   # brain memory: doors that would not open
    stores: list[Pos] = field(default_factory=list)  # town only: entrance of store N+1
    unknown: dict[Pos, str] = field(default_factory=dict)  # unidentified glyphs on screen
    hazards: set[Pos] = field(default_factory=set)   # brain: creatures to keep away from
    screen: tuple[int, int, int, int] = (0, 0, 0, 0)  # map x, y, width, height on screen

    def on_screen(self, pos: Pos) -> bool:
        """Whether the screen shows ``pos`` (an unset screen shows the whole map)."""
        x, y, w, h = self.screen
        return w == 0 or (x <= pos[0] < x + w and y <= pos[1] < y + h)

    @property
    def monsters(self) -> set[Pos]:
        return set(self.creatures)

    def inside(self, x: int, y: int) -> bool:
        return 0 <= x < self.cols and 0 <= y < self.rows

    def type_at(self, x: int, y: int) -> int:
        return self.types[y * self.cols + x]

    def tiles_of(self, tile_type: int) -> set[Pos]:
        return {(i % self.cols, i // self.cols) for i, t in enumerate(self.types) if t == tile_type}

    def stairs_down(self) -> set[Pos]:
        return self.tiles_of(TYPE_STAIRS_DN)

    def stairs_up(self) -> set[Pos]:
        return self.tiles_of(TYPE_STAIRS_UP)

    def passable(self, x: int, y: int, *, avoid_monsters: bool, doors: bool = False) -> bool:
        if not self.inside(x, y) or (x, y) in self.blocked:
            return False
        if avoid_monsters and (x, y) in self.creatures:
            return False
        t = self.type_at(x, y)
        if t == TYPE_DOOR_OPEN and self.dlvl == 0:
            return False  # town store entrance
        return t in WALKABLE_TYPES or (doors and t == TYPE_DOOR_CLOSED)

    def neighbors(self, x: int, y: int):  # type: ignore[no-untyped-def]
        for dx, dy in DIRS:
            if self.inside(x + dx, y + dy):
                yield x + dx, y + dy

    def step_toward(self, goals: set[Pos], *, avoid_monsters: bool,
                    doors: bool = True, keep_clear: bool = False) -> tuple[int, int] | None:
        """First (dx, dy) of a cheapest known-tile path to any goal; (0, 0) if on one.

        A step costs 1, plus ``TRAP_COST`` onto a known trap, ``UNKNOWN_COST``
        next to an unidentified glyph and twice that onto one: a detour of up
        to that many steps is preferred, but if it is the only way the path goes
        anyway (next to the glyph the brain looks at it first).
        ``keep_clear`` also refuses tiles next to a visible creature (fleeing).
        """
        start = self.pos
        goals = goals - self.blocked   # a blocked tile is no goal either (round 17)
        danger = ({(x + dx, y + dy) for x, y in self.creatures for dx in (-1, 0, 1) for dy in (-1, 0, 1)}
                  if keep_clear else set())
        near_unknown, near_hazard = self.near_costly()
        if start in goals:
            return (0, 0)
        found = self.route(goals, start, danger, near_unknown, near_hazard, avoid_monsters, doors)
        return None if found is None else found[0]

    def path_steps(self, goals: set[Pos], *, avoid_monsters: bool, doors: bool = True) -> int | None:
        """Number of steps of the cheapest known-tile path to any goal, as
        ``step_toward`` walks it (trap and glyph costs choose the path but do
        not count as steps); None if unreachable."""
        goals = goals - self.blocked
        if self.pos in goals:
            return 0
        near_unknown, near_hazard = self.near_costly()
        found = self.route(goals, self.pos, set(), near_unknown, near_hazard, avoid_monsters, doors)
        return None if found is None else found[1]

    def near_costly(self) -> tuple[set[Pos], set[Pos]]:
        """Squares next to an unidentified glyph, and next to a hazard."""
        def around(tiles: set[Pos]) -> set[Pos]:
            return {(x + dx, y + dy) for x, y in tiles for dx in (-1, 0, 1) for dy in (-1, 0, 1)}
        return around(set(self.unknown)), around(self.hazards)

    def route(self, goals: set[Pos], start: Pos, danger: set[Pos], near_unknown: set[Pos],
              near_hazard: set[Pos], avoid_monsters: bool, doors: bool) -> tuple[tuple[int, int], int] | None:
        """Dijkstra over known tiles: (first step, number of steps) along the
        cheapest path to the nearest goal. Hot path: ``passable`` and
        ``neighbors`` are inlined (same neighbour order, same tie-break)."""
        cols, rows, types = self.cols, self.rows, self.types
        blocked, unknown = self.blocked, self.unknown
        creatures = self.creatures if avoid_monsters else ()
        town = self.dlvl == 0
        walkable = WALKABLE_TYPES
        heappush, heappop = heapq.heappush, heapq.heappop
        cost = {start: 0}
        previous = {start: start}
        heap = [(0, 0, start)]   # (cost, push order, tile): FIFO among equals, as in BFS
        pushed = 0
        while heap:
            here_cost, _, here = heappop(heap)
            if here_cost > cost[here]:
                continue
            if here in goals:
                steps = 1
                while previous[here] != start:
                    here = previous[here]
                    steps += 1
                return (here[0] - start[0], here[1] - start[1]), steps
            hx, hy = here
            for dx, dy in DIRS:
                x, y = hx + dx, hy + dy
                if not (0 <= x < cols and 0 <= y < rows):
                    continue
                nxt = (x, y)
                t = types[y * cols + x]
                if nxt not in goals:
                    if nxt in danger or nxt in blocked or nxt in creatures:
                        continue
                    if t == TYPE_DOOR_OPEN and town:
                        continue   # town store entrance
                    if t not in walkable and not (doors and t == TYPE_DOOR_CLOSED):
                        continue
                step = 1
                if t == TYPE_TRAP:
                    step += TRAP_COST
                if nxt in near_unknown:
                    step += UNKNOWN_COST
                if nxt in near_hazard:
                    step += HAZARD_COST
                if nxt in unknown:
                    step += 2 * UNKNOWN_COST
                new_cost = here_cost + step
                if new_cost < cost.get(nxt, new_cost + 1):
                    cost[nxt] = new_cost
                    previous[nxt] = here
                    pushed += 1
                    heappush(heap, (new_cost, pushed, nxt))
        return None

    def frontier(self, *, traps: bool = False) -> set[Pos]:
        """Known passable tiles (or closed doors) touching an unknown tile.

        A known trap is a frontier tile only with ``traps`` (nothing else is left).
        A tile under a creature or next to a hazard is none: a goal is entered
        whatever stands on it (M4 round 52: explore walked into a Yellow
        Jelly sitting on the edge, seed 1016).
        """
        near_hazard = {(hx + dx, hy + dy) for hx, hy in self.hazards for dx in (-1, 0, 1) for dy in (-1, 0, 1)}
        exclude = self.blocked | set(self.unknown) | set(self.creatures) | near_hazard
        town = self.dlvl == 0
        return {p for p, t in self.terrain_frontier(traps)
                if p not in exclude and not (t == TYPE_DOOR_OPEN and town)}

    def terrain_frontier(self, traps: bool) -> list[tuple[Pos, int]]:
        """Walkable tiles (or closed doors) touching an unknown tile, with their
        type: the part of ``frontier`` that depends on the map alone, cached
        per map contents (several layers ask each step)."""
        key = (traps, hash(tuple(self.types)))
        cache = self.__dict__.setdefault("_frontier_cache", {})
        if key in cache:
            return cache[key]
        cols, rows, types = self.cols, self.rows, self.types
        out = []
        for i, t in enumerate(types):
            if (t not in WALKABLE_TYPES and t != TYPE_DOOR_CLOSED) or (t == TYPE_TRAP and not traps):
                continue
            x, y = i % cols, i // cols
            for dx, dy in DIRS:
                nx, ny = x + dx, y + dy
                if 0 <= nx < cols and 0 <= ny < rows and types[ny * cols + nx] == UNKNOWN:
                    out.append(((x, y), t))
                    break
        cache[key] = out
        return out

    def search_spots(self, searched: set[Pos], *, traps: bool = False) -> set[Pos]:
        """Passable tiles next to a wall with unknown space directly behind it
        (a known trap only with ``traps``)."""
        out = set()
        for i, t in enumerate(self.types):
            if (t not in WALKABLE_TYPES or (t == TYPE_TRAP and not traps)
                    or (i % self.cols, i // self.cols) in searched
                    or (i % self.cols, i // self.cols) in self.unknown):
                continue
            x, y = i % self.cols, i // self.cols
            for dx, dy in DIRS:
                wx, wy, bx, by = x + dx, y + dy, x + 2 * dx, y + 2 * dy
                if (self.inside(bx, by) and self.type_at(wx, wy) == WALL
                        and self.type_at(bx, by) == UNKNOWN):
                    out.add((x, y))
                    break
        return out


def sealed_search_spots(view: "View", searched: set[Pos]) -> set[Pos]:
    """Search spots when sealed in: reachable tiles next to a wall whose far
    side is unknown, or is floor this region cannot reach (a wall one thick
    between two known areas is likely a secret door)."""
    region = {view.pos}
    todo = [view.pos]
    while todo:
        x, y = todo.pop()
        for nxt in view.neighbors(x, y):
            if nxt not in region and view.passable(*nxt, avoid_monsters=False, doors=True):
                region.add(nxt)
                todo.append(nxt)
    out = set()
    for x, y in region - searched:
        for dx, dy in DIRS:
            wx, wy, bx, by = x + dx, y + dy, x + 2 * dx, y + 2 * dy
            if not view.inside(bx, by) or view.type_at(wx, wy) != WALL:
                continue
            beyond = view.type_at(bx, by)
            if beyond == UNKNOWN or (beyond in WALKABLE_TYPES and (bx, by) not in region):
                out.add((x, y))
                break
    return out


def screen_to_map(game: Game, obs: Observation, col: int, row: int) -> Pos:
    abi = game.abi
    return (obs.zp[abi.zp_view_x] + col - abi.hal_layout_viewport_x,
            obs.zp[abi.zp_view_y] + row - abi.hal_layout_viewport_y)


@lru_cache(maxsize=4)
def tile_type_table(flag_visited: int) -> tuple[int, ...]:
    """Map tile byte -> view type: unknown until visited; secret doors and
    every wall kind read as wall."""
    out = []
    for tile in range(256):
        if not tile & flag_visited:
            out.append(UNKNOWN)
        elif tile >> 4 == TYPE_SECRET or tile >> 4 in (0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0xC, 0xD):
            out.append(WALL)
        else:
            out.append(tile >> 4)
    return tuple(out)


def build_view(game: Game, obs: Observation, tiles: bytes, levels: bytes | None = None) -> View:
    """``levels`` is the resident ``cr_level`` table, read once per observation."""
    abi = game.abi
    cols, rows = abi.hal_layout_map_cols, abi.hal_layout_map_rows
    table = tile_type_table(abi.FLAG_VISITED)
    types = [table[tile] for tile in tiles]
    by_pos = {}
    size = abi.MONSTER_ENTRY_SIZE
    for slot in range(abi.MAX_MONSTERS):
        rec = obs.monsters[slot * size:(slot + 1) * size]
        if rec[abi.MX_TYPE] != abi.EMPTY_SLOT:
            by_pos[(rec[abi.MX_X], rec[abi.MX_Y])] = rec[abi.MX_TYPE]
    creatures = {}
    unknown = {}
    vx, vy = abi.hal_layout_viewport_x, abi.hal_layout_viewport_y
    for row in range(vy, vy + abi.hal_layout_viewport_h):
        line = obs.rows[row]
        for col in range(vx, vx + abi.hal_layout_viewport_w):
            if line[col].isalpha():
                pos = screen_to_map(game, obs, col, row)
                kind = by_pos.get(pos)
                level = levels[kind] if levels is not None and kind is not None and kind < len(levels) else 0
                creatures[pos] = Creature(line[col], level)
            elif is_unknown_glyph(line[col]):
                unknown[screen_to_map(game, obs, col, row)] = line[col]
    stores = []
    if obs.dlvl == 0:
        xs = game.mon.mem_get(abi.store_door_x, abi.STORE_COUNT, game.ram)
        ys = game.mon.mem_get(abi.store_door_y, abi.STORE_COUNT, game.ram)
        stores = list(zip(xs, ys))
    screen = (*screen_to_map(game, obs, vx, vy), abi.hal_layout_viewport_w, abi.hal_layout_viewport_h)
    return View(cols, rows, types, obs.pos, obs.dlvl, creatures, stores=stores, unknown=unknown, screen=screen)
