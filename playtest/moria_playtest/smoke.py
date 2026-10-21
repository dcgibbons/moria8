"""``make playtest-smoke``: a <=30 s production-path gate for the playtester.

Title snapshot -> seeded Half-Troll Warrior chargen through the real prompts ->
town command prompt, then checks every decoder against the screen.
"""

from __future__ import annotations

import json
import sys
import time

from .game import Mode, Observation
from .launch import PLAYTEST_OUT, find_vice
from .worker import Worker

BUDGET_SECONDS = 30.0


def status_numbers(obs: Observation) -> dict[str, int]:
    """Parse LV/DL from status row 21 and HP from row 23."""
    row21, row23 = obs.rows[21], obs.rows[23]
    lv = int(row21.split("LV:")[1].split()[0])
    dl = int(row21.split("DL:")[1].split()[0])
    hp, mhp = row23.split("HP:")[1].split()[0].split("/")
    return {"clvl": lv, "dlvl": dl, "hp": int(hp), "mhp": int(mhp)}


def checks(obs: Observation) -> list[str]:
    abi = obs.abi
    assert abi is not None
    failures: list[str] = []
    if obs.mode != Mode.COMMAND:
        failures.append(f"expected COMMAND mode in town, got {obs.mode.value}")
        return failures
    shown = status_numbers(obs)
    for key, value in (("clvl", obs.clvl), ("dlvl", obs.dlvl), ("hp", obs.hp), ("mhp", obs.mhp)):
        if shown[key] != value:
            failures.append(f"status line {key}={shown[key]} but memory has {value}")
    if obs.dlvl != 0 or obs.clvl != 1:
        failures.append(f"new character should be clvl 1 in town, got clvl {obs.clvl} DL {obs.dlvl}")
    x, y = obs.pos
    if not (0 <= x < abi.hal_layout_map_cols and 0 <= y < abi.hal_layout_map_rows):
        failures.append(f"player position {obs.pos} outside the map")
    if obs.player[abi.PL_RACE] != 7 or obs.player[abi.PL_CLASS] != 0:
        failures.append("character is not a Half-Troll Warrior")
    if obs.game_flags & (abi.GAME_FLAG_OVER | abi.GAME_FLAG_WIZARD):
        failures.append(f"unexpected game flags ${obs.game_flags:02X}")
    if "@" not in "".join(obs.rows[1:21]):
        failures.append("player glyph not on screen")
    return failures


def main() -> int:
    start = time.monotonic()
    result: dict[str, object] = {"vice": find_vice()}
    worker = Worker(PLAYTEST_OUT / "smoke")
    try:
        obs = worker.start_at_title()
        game = worker.game
        assert game is not None
        result["vice_info"] = game.mon.vice_info()
        game.seed_title(1)
        modes: list[str] = []
        while obs.mode != Mode.COMMAND and game.step < 40:
            key = game.chargen_key(obs) if obs.mode == Mode.CHARGEN else 0x20
            obs = game.press(key)
            modes.append(f"{obs.mode.value}:{obs.stage}")
        result["modes"] = modes
        result["final"] = obs.summary()
        failures = checks(obs)
    finally:
        worker.stop()
    elapsed = time.monotonic() - start
    if elapsed > BUDGET_SECONDS:
        failures.append(f"smoke took {elapsed:.1f}s (budget {BUDGET_SECONDS:.0f}s)")
    result["elapsed_s"] = round(elapsed, 2)
    result["failures"] = failures
    print(json.dumps(result, indent=1))
    print("playtest-smoke:", "PASS" if not failures else "FAIL")
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
