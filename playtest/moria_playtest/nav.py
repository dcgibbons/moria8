"""Privileged map access and BFS paths.

Used by M0 measurement and the guided fuzz only. The fair-play brain (M1) must
not use this module: it reads the whole map regardless of FLAG_VISITED.
"""

from __future__ import annotations

from collections import deque

from .game import Game

# Mirrors walkable_table in core/player_move.s (tile type = high nibble).
WALKABLE_TYPES = {0x0, 0x7, 0x9, 0xA, 0xB, 0xE}
TYPE_DOOR_OPEN = 0x7
TYPE_DOOR_CLOSED = 0x8

DIRECTION_KEYS = {
    (0, -1): ord("K"), (0, 1): ord("J"), (-1, 0): ord("H"), (1, 0): ord("L"),
    (-1, -1): ord("Y"), (1, -1): ord("U"), (-1, 1): ord("B"), (1, 1): ord("N"),
}


def read_map(game: Game) -> bytes:
    if hasattr(game, "read_map"):   # a backend that keeps its own copy (X16Game)
        return game.read_map()
    abi = game.abi
    size = abi.hal_layout_map_cols * abi.hal_layout_map_rows
    return game.mon.mem_get(abi.MAP_BASE, size, game.map_bank)


def find_tiles(tiles: bytes, cols: int, tile_type: int) -> list[tuple[int, int]]:
    return [(i % cols, i // cols) for i, t in enumerate(tiles) if t >> 4 == tile_type]


def first_step(tiles: bytes, cols: int, rows: int, start: tuple[int, int],
               goals: set[tuple[int, int]], *, in_town: bool,
               through_closed_doors: bool = True) -> tuple[int, int] | None:
    """Direction (dx, dy) of the first step on a shortest path to any goal."""
    if start in goals:
        return (0, 0)

    def passable(x: int, y: int) -> bool:
        tile_type = tiles[y * cols + x] >> 4
        if (x, y) in goals:
            return True
        if in_town and tile_type == TYPE_DOOR_OPEN:
            return False  # town store entrances
        if tile_type == TYPE_DOOR_CLOSED:
            return through_closed_doors
        return tile_type in WALKABLE_TYPES

    previous: dict[tuple[int, int], tuple[int, int]] = {start: start}
    queue = deque([start])
    while queue:
        x, y = queue.popleft()
        for dx, dy in DIRECTION_KEYS:
            nxt = (x + dx, y + dy)
            if nxt in previous or not (0 <= nxt[0] < cols and 0 <= nxt[1] < rows):
                continue
            if not passable(*nxt):
                continue
            previous[nxt] = (x, y)
            if nxt in goals:
                node = nxt
                while previous[node] != start:
                    node = previous[node]
                return node[0] - start[0], node[1] - start[1]
            queue.append(nxt)
    return None
