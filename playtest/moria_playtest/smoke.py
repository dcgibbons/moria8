"""``make playtest-smoke``: a <=30 s production-path gate for the playtester.

Title snapshot -> seeded Half-Troll Warrior chargen through the real prompts ->
town command prompt, then checks every decoder against the screen. Then two
game paths the M3 bot found crashing (AI_PLAYTEST_DESIGN §14.10): a throw
through the ``?`` item list, and a level-up followed by a turn (the deferred
mana/spell recalc at the top of ``main_loop``).
"""

from __future__ import annotations

import json
import sys
import time

from .game import KEY_SPACE, GameFault, Mode, Observation
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


def settle(game, obs: Observation) -> Observation:  # type: ignore[no-untyped-def]
    """Dismiss -more- screens back to the command prompt."""
    while obs.mode == Mode.DISMISS:
        obs = game.press(KEY_SPACE)
    return obs


def overlay_paths(game) -> list[str]:  # type: ignore[no-untyped-def]
    """Throw via the item list, then a wizard level-up and one more turn."""
    failures: list[str] = []
    try:
        obs = game.press(0xD4)                               # SHIFT+T: throw
        for key in (ord("?"), ord("A"), ord("J")):          # list, first item, south
            obs = game.press(key)
        obs = settle(game, obs)
        if obs.mode != Mode.COMMAND:
            failures.append(f"throw via the item list ended in {obs.mode.value}")
        obs = settle(game, game.press(0x17))                 # CTRL+W (after any -more-)
        if "WIZARD?" not in obs.rows[0] + obs.rows[1]:
            failures.append("CTRL+W did not ask WIZARD? (Y/N)")
        obs = settle(game, game.press(ord("Y")))             # wizard on
        obs = settle(game, game.press(0x17))                 # wizard menu
        obs = settle(game, game.press(ord("X")))             # gain one level
        obs = settle(game, game.press(ord("5")))             # a turn: main_loop runs the recalc
        if obs.mode != Mode.COMMAND or obs.clvl != 2:
            failures.append(f"level-up path ended in {obs.mode.value} at clvl {obs.clvl}")
    except GameFault as fault:
        failures.append(f"{fault.kind}: {fault.detail}")
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
        if not failures:
            failures += overlay_paths(game)
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
