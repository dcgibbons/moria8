"""Auditor v0 (§6.8): privileged checks every stop; never influences the brain.

Findings are classed ``game`` (a defect in Moria8) or ``bot`` (bot-quality
data such as unknown prompts and stalls), so the two never mix.
"""

from __future__ import annotations

from dataclasses import dataclass

from .game import Mode, Observation
from .view import WALKABLE_TYPES


@dataclass(frozen=True)
class Finding:
    kind: str
    cls: str      # "game" or "bot"
    detail: str

    def key(self) -> tuple[str, str]:
        return self.kind, self.detail


def monster_positions(obs: Observation) -> set[tuple[int, int]]:
    abi = obs.abi
    assert abi is not None
    size = abi.MONSTER_ENTRY_SIZE
    positions = set()
    for slot in range(abi.MAX_MONSTERS):
        rec = obs.monsters[slot * size:(slot + 1) * size]
        if rec[abi.MX_TYPE] != abi.EMPTY_SLOT:
            positions.add((rec[abi.MX_X], rec[abi.MX_Y]))
    return positions


def status_numbers(obs: Observation) -> dict[str, int] | None:
    """LV/DL from status row 21 and HP from row 23, or None if not parseable."""
    try:
        row21, row23 = obs.rows[21], obs.rows[23]
        hp, mhp = row23.split("HP:")[1].split()[0].split("/")
        return {"clvl": int(row21.split("LV:")[1].split()[0]),
                "dlvl": int(row21.split("DL:")[1].split()[0]), "hp": int(hp), "mhp": int(mhp)}
    except (IndexError, ValueError):
        return None


class Auditor:
    def __init__(self) -> None:
        self.command_sp: int | None = None
        self.reported_unknown: set[str] = set()

    def learn(self, obs: Observation) -> None:
        """Record the command-prompt SP baseline if this is the first command stop."""
        if obs.mode == Mode.COMMAND and self.command_sp is None:
            self.command_sp = obs.sp

    def check(self, obs: Observation, tiles: bytes | None) -> list[Finding]:
        if obs.mode == Mode.UNKNOWN:
            label = obs.stage or (obs.rows[0].strip()[:40] or "(blank)")
            if label not in self.reported_unknown:
                self.reported_unknown.add(label)
                return [Finding("unknown_prompt", "bot", label)]
            return []
        if obs.mode != Mode.COMMAND:
            return []
        findings: list[Finding] = []
        self.learn(obs)
        if obs.sp != self.command_sp:
            findings.append(Finding("stack", "game", f"SP at command prompt ${obs.sp:02X}, "
                                    f"expected ${self.command_sp:02X}"))
        findings += self.state_invariants(obs, tiles)
        findings += self.view_consistency(obs)
        return findings

    def state_invariants(self, obs: Observation, tiles: bytes | None) -> list[Finding]:
        abi = obs.abi
        assert abi is not None
        out: list[Finding] = []
        if obs.hp > obs.mhp:
            out.append(Finding("state_invariant", "game", f"HP {obs.hp} exceeds max HP {obs.mhp}"))
        if tiles is None:
            return out
        cols = abi.hal_layout_map_cols
        x, y = obs.pos
        if tiles[y * cols + x] >> 4 not in WALKABLE_TYPES:
            out.append(Finding("state_invariant", "game",
                               f"player on non-walkable tile ${tiles[y * cols + x]:02X} at {obs.pos}"))
        monsters = monster_positions(obs)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                nx, ny = x + dx, y + dy
                if (dx, dy) == (0, 0) or not (0 <= nx < cols and 0 <= ny < abi.hal_layout_map_rows):
                    continue
                flagged = bool(tiles[ny * cols + nx] & abi.FLAG_OCCUPIED)
                if flagged != ((nx, ny) in monsters):
                    out.append(Finding("state_invariant", "game",
                                       f"FLAG_OCCUPIED={int(flagged)} at {(nx, ny)} disagrees "
                                       f"with the monster table"))
        return out

    def view_consistency(self, obs: Observation) -> list[Finding]:
        abi = obs.abi
        assert abi is not None
        shown = status_numbers(obs)
        if shown is None:
            return [Finding("view_mismatch", "game", "status line not parseable at command prompt")]
        out = [Finding("view_mismatch", "game", f"status {key}={shown[key]} but memory has {value}")
               for key, value in (("clvl", obs.clvl), ("dlvl", obs.dlvl), ("hp", obs.hp),
                                  ("mhp", obs.mhp)) if shown[key] != value]
        col = obs.pos[0] - obs.zp[abi.zp_view_x] + abi.hal_layout_viewport_x
        row = obs.pos[1] - obs.zp[abi.zp_view_y] + abi.hal_layout_viewport_y
        if not (0 <= row < 25 and 0 <= col < 40) or obs.rows[row][col] != "@":
            out.append(Finding("view_mismatch", "game",
                               f"player glyph not at screen ({col},{row}) for map {obs.pos}"))
        return out
