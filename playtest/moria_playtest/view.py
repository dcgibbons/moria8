"""Fair-play view (§6.5): what a player could know, and nothing more.

- Map: read from memory but gated by ``FLAG_VISITED``; secret doors read as
  wall; unvisited tiles are unknown. (Unfound traps are plain floor in memory.)
- Creatures: whatever creature glyphs the *screen* shows in the viewport. The
  monster table is consulted only to identify a glyph already on screen
  (creature level), as a player would by looking at it.
- Town: the store entrances (a fixed layout every player knows).
The brain sees only this view. Privileged state stays with the auditor.
"""

from __future__ import annotations

import heapq
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

        A step costs 1, plus ``TRAP_COST`` onto a known trap: a detour of up to
        that many steps is preferred, but a trap that is the only way is crossed.
        ``keep_clear`` also refuses tiles next to a visible creature (fleeing).
        """
        start = self.pos
        danger = ({(x + dx, y + dy) for x, y in self.creatures for dx in (-1, 0, 1) for dy in (-1, 0, 1)}
                  if keep_clear else set())
        if start in goals:
            return (0, 0)
        cost = {start: 0}
        previous = {start: start}
        heap = [(0, 0, start)]   # (cost, push order, tile): FIFO among equals, as in BFS
        pushed = 0
        while heap:
            here_cost, _, here = heapq.heappop(heap)
            if here_cost > cost[here]:
                continue
            if here in goals:
                while previous[here] != start:
                    here = previous[here]
                return here[0] - start[0], here[1] - start[1]
            for nxt in self.neighbors(*here):
                if nxt not in goals and (nxt in danger or not self.passable(
                        *nxt, avoid_monsters=avoid_monsters, doors=doors)):
                    continue
                step = 1 + (TRAP_COST if self.type_at(*nxt) == TYPE_TRAP else 0)
                if here_cost + step < cost.get(nxt, here_cost + step + 1):
                    cost[nxt] = here_cost + step
                    previous[nxt] = here
                    pushed += 1
                    heapq.heappush(heap, (here_cost + step, pushed, nxt))
        return None

    def frontier(self, *, traps: bool = False) -> set[Pos]:
        """Known passable tiles (or closed doors) touching an unknown tile.

        A known trap is a frontier tile only with ``traps`` (nothing else is left).
        """
        out = set()
        for i, t in enumerate(self.types):
            if (t not in WALKABLE_TYPES and t != TYPE_DOOR_CLOSED) or (t == TYPE_TRAP and not traps):
                continue
            x, y = i % self.cols, i // self.cols
            if (x, y) in self.blocked or (t == TYPE_DOOR_OPEN and self.dlvl == 0):
                continue
            if any(self.type_at(nx, ny) == UNKNOWN for nx, ny in self.neighbors(x, y)):
                out.add((x, y))
        return out

    def search_spots(self, searched: set[Pos], *, traps: bool = False) -> set[Pos]:
        """Passable tiles next to a wall with unknown space directly behind it
        (a known trap only with ``traps``)."""
        out = set()
        for i, t in enumerate(self.types):
            if (t not in WALKABLE_TYPES or (t == TYPE_TRAP and not traps)
                    or (i % self.cols, i // self.cols) in searched):
                continue
            x, y = i % self.cols, i // self.cols
            for dx, dy in DIRS:
                wx, wy, bx, by = x + dx, y + dy, x + 2 * dx, y + 2 * dy
                if (self.inside(bx, by) and self.type_at(wx, wy) == WALL
                        and self.type_at(bx, by) == UNKNOWN):
                    out.add((x, y))
                    break
        return out


def screen_to_map(game: Game, obs: Observation, col: int, row: int) -> Pos:
    abi = game.abi
    return (obs.zp[abi.zp_view_x] + col - abi.hal_layout_viewport_x,
            obs.zp[abi.zp_view_y] + row - abi.hal_layout_viewport_y)


def build_view(game: Game, obs: Observation, tiles: bytes, levels: bytes | None = None) -> View:
    """``levels`` is the resident ``cr_level`` table, read once per observation."""
    abi = game.abi
    cols, rows = abi.hal_layout_map_cols, abi.hal_layout_map_rows
    types = []
    for tile in tiles:
        if not tile & abi.FLAG_VISITED:
            types.append(UNKNOWN)
        elif tile >> 4 == TYPE_SECRET:
            types.append(WALL)
        elif tile >> 4 in (0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0xC, 0xD):
            types.append(WALL)
        else:
            types.append(tile >> 4)
    by_pos = {}
    size = abi.MONSTER_ENTRY_SIZE
    for slot in range(abi.MAX_MONSTERS):
        rec = obs.monsters[slot * size:(slot + 1) * size]
        if rec[abi.MX_TYPE] != abi.EMPTY_SLOT:
            by_pos[(rec[abi.MX_X], rec[abi.MX_Y])] = rec[abi.MX_TYPE]
    creatures = {}
    vx, vy = abi.hal_layout_viewport_x, abi.hal_layout_viewport_y
    for row in range(vy, vy + abi.hal_layout_viewport_h):
        line = obs.rows[row]
        for col in range(vx, vx + abi.hal_layout_viewport_w):
            if line[col].isalpha():
                pos = screen_to_map(game, obs, col, row)
                kind = by_pos.get(pos)
                level = levels[kind] if levels is not None and kind is not None and kind < len(levels) else 0
                creatures[pos] = Creature(line[col], level)
    stores = []
    if obs.dlvl == 0:
        xs = game.mon.mem_get(abi.store_door_x, abi.STORE_COUNT, game.ram)
        ys = game.mon.mem_get(abi.store_door_y, abi.STORE_COUNT, game.ram)
        stores = list(zip(xs, ys))
    return View(cols, rows, types, obs.pos, obs.dlvl, creatures, stores=stores)
