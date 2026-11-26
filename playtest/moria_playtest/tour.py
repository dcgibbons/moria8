"""The playtest gate's scripted tour (``make playtest-gate``): on one target, a
new Human Mage does the actions the bot reaches late or by chance, through the
real prompts. A step whose screen is not the one expected, or a hang, fails.

- a store buy (2026-11-15: the BBC's and Apple IIe's first buy ran past
  OVL.TOWN's end and panicked);
- a cast from a second book through the book prompt's ``?`` list (the Atari's
  came back into OVL_HELP's bytes and hung);
- a Home deposit and retrieval;
- a drop and a pick-up;
- an ego arrow shot from a bow into a townsperson (2026-11-15: the C64's
  tramp_ego_apply_damage, called from OVL.ITEMS for ego ammunition, banked
  the KERNAL in over the overlay and jammed the machine);
- the in-game ``? -> L`` legal viewer streaming ``LICENSE`` and
  ``SOURCE-OFFER`` and returning to play.

Usage: ``python -m moria_playtest.tour TARGET OUT_DIR`` writes ``OUT_DIR/tour.json``.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Callable

from .game import KEY_RETURN, KEY_SPACE, GameFault, Mode, Observation
from .launch import Build
from .ports import PORTS
from .nav import read_map
from .view import DIRS
from .worker import Worker

_TOOLS_DIR = str(Path(__file__).resolve().parents[2] / "tools")
if _TOOLS_DIR not in sys.path:
    sys.path.insert(0, _TOOLS_DIR)
from item_ids import (  # noqa: E402
    FI_EMPTY,
    ITEM_PAGE_ARROW,
    ITEM_PAGE_BIT,
    ITEM_PAGE_SHORT_BOW,
    ITEM_PAGE_SPELLBOOK_MAGICK_I,
    ITEM_SLOT_ARROW,
    ITEM_SLOT_SHORT_BOW,
    ITEM_SLOT_SPELLBOOK_MAGICK_I,
)

KEY_ESC = 0x1B
SEED = 1004
PL_GOLD = 43                       # core/6502/player.s PL_GOLD_0..2
WEAPONSMITH_DOOR = (39, 6)         # core/6502/dungeon_data.s store_door_x/y[2]
HOME_DOOR = (51, 16)               # store_door_x/y[STORE_HOME]
INV_FIELDS = ("inv_item_id", "inv_qty", "inv_p1", "inv_to_hit", "inv_to_dam", "inv_to_ac", "inv_flags", "inv_ego")
PACK_SLOTS = 22
IF_KNOWN = 0x02
EGO_ARROW_SLAY_EVIL = 44           # core/6502/item_defs.s EGO_AMMO_SLAY_EVIL
EQUIP_WEAPON = 22                  # core/6502/item_defs.s
KEY_FIRE = 0xC6                    # SHIFT+F: the wielded launcher at the first matching ammunition
SHOT_RANGE = 2                     # squares to the townsperson
STREET = (39, 8)                   # the street between the store rows (core/6502/dungeon_data.s store_pos_y 2 and 12)
SHOTS = 20                         # tries for one hit: a seed of misses runs long (BBC, 2026-11-15)
SHOT_TOHIT = 20                    # on the bow and the arrows
MX_X, MX_Y, MX_TYPE, MX_HP_LO, MX_HP_HI, MX_SLEEP = 0, 1, 2, 3, 4, 7   # core/6502/monster.s


class TourFailed(Exception):
    pass


class Tour:
    def __init__(self, worker: Worker, obs: Observation) -> None:
        self.worker = worker
        game = worker.game
        assert game is not None
        self.game = game
        self.abi = game.abi
        self.obs = obs
        self.steps: list[str] = []
        self.bought = 0   # the pack slot of the item the store sold

    # -- memory

    def sym(self, name: str) -> int:
        return self.abi.all_symbols[name][0]

    def poke(self, addr: int, data: bytes) -> None:
        self.game.mon.mem_set(addr, data, self.game.ram)

    def peek(self, addr: int, length: int) -> bytes:
        return self.game.mon.mem_get(addr, length, self.game.ram)

    def seed_slot(self, slot: int, fields: tuple[int, ...]) -> None:
        for name, value in zip(INV_FIELDS, fields):
            self.poke(self.sym(name) + slot, bytes([value]))

    def pack(self) -> bytes:
        return self.peek(self.sym("inv_item_id"), PACK_SLOTS)

    # -- keys and screens

    def text(self) -> str:
        return "\n".join(self.obs.rows)

    def press(self, key: int) -> None:
        self.obs = self.game.press(key)

    def keys(self, text: str) -> None:
        for ch in text:
            self.press(KEY_RETURN if ch == "\r" else ord(ch))

    def settle(self) -> None:
        """Past -more- to the command prompt (or the screen that stays)."""
        for _ in range(8):
            if self.obs.mode != Mode.DISMISS:
                return
            self.press(KEY_SPACE)

    def expect(self, what: str, ok: Callable[[], bool]) -> None:
        if not ok():
            raise TourFailed(f"{what}: screen row 0 {self.obs.rows[0].strip()!r} ({self.obs.mode.value})")
        self.steps.append(what)

    def at_command(self, what: str) -> None:
        self.settle()
        self.expect(what, lambda: self.obs.mode == Mode.COMMAND)

    def _set_player_pos(self, x: int, y: int) -> None:
        self.poke(self.sym("zp_player_x"), bytes([x]))
        self.poke(self.sym("zp_player_y"), bytes([y]))
        if self.game.port.platform == "cpm":
            pl_addr = self.sym("player_data")
            self.poke(pl_addr + 49, bytes([x]))   # PL_MAP_X
            self.poke(pl_addr + 50, bytes([y]))   # PL_MAP_Y

    def walk_in(self, door: tuple[int, int]) -> None:
        """Stand south of a town door and step onto it."""
        self._set_player_pos(door[0], door[1] + 1)
        self.press(ord("K"))

    # -- the tour

    def chargen(self) -> None:
        self.game.seed_title(SEED)
        for _ in range(60):
            if self.obs.mode == Mode.COMMAND:
                break
            key = self.game.chargen_key(self.obs, race="A", klass="B") if self.obs.mode == Mode.CHARGEN \
                else KEY_SPACE
            self.press(key)
        self.expect("chargen reaches the town", lambda: self.obs.mode == Mode.COMMAND and self.obs.dlvl == 0)

    def store_buy(self) -> None:
        before = self.pack()
        self.poke(self.sym("player_data") + PL_GOLD, (50000).to_bytes(3, "little"))
        self.walk_in(WEAPONSMITH_DOOR)
        self.expect("the Weaponsmith's menu", lambda: "B)uy" in self.text())
        # Over 10 gp: the haggle (core/6502/ui_store.s sells 10 gp and less at a
        # fixed price; the BBC's first item was a 1 gp Broken Dagger).
        letter = next((row.strip()[0] for row in self.obs.rows[3:20]
                       if len(row.strip()) > 3 and row.strip()[1] == ")" and row.split()[-1:] == ["GP"]
                       and row.split()[-2].isdigit() and int(row.split()[-2]) > 10), None)
        self.expect("an item for sale over 10 gp", lambda: letter is not None)
        self.press(ord("B"))
        self.expect("the buy prompt", lambda: "Buy which item" in self.text())
        self.press(ord(letter.upper()))   # type: ignore[union-attr]
        for _ in range(4):   # a fixed price, or the haggle at the asking price
            text = self.text()
            if "Buy? (Y/N)" in text or "Take it? (Y/N)" in text:
                self.press(ord("Y"))
            elif "Your offer?" in text:
                ask = next((row.split("Asks ")[1].split(" gp")[0] for row in self.obs.rows if "Asks " in row), "")
                self.expect("the asking price", lambda: ask.isdigit())
                self.keys(ask + "\r")
            else:
                break
        self.settle()
        self.expect("the item bought, back at the menu",
                    lambda: self.pack().count(0xFF) == before.count(0xFF) - 1 and "B)uy" in self.text())
        self.bought = next(slot for slot, (old, new) in enumerate(zip(before, self.pack())) if old != new)
        self.press(ord("Q"))
        self.at_command("out of the store")

    def second_book(self) -> None:
        pack = self.pack()
        self.seed_slot(
            pack.index(FI_EMPTY),
            (ITEM_SLOT_SPELLBOOK_MAGICK_I, 1, 0, 0, 0, 0, IF_KNOWN, ITEM_PAGE_SPELLBOOK_MAGICK_I),
        )
        self.press(ord("M"))
        self.expect("the two-book prompt",
                    lambda: "Spell book (a-b)?" in self.text() or "Use which spell book? (a-b" in self.text())
        self.press(ord("?"))
        self.expect("the book list", lambda: "Magick I" in self.text())
        self.press(ord("B"))
        self.settle()
        self.expect("a level 1 Mage knows no Magick I spell", lambda: "You don't know that spell." in self.text()
                    or self.obs.mode == Mode.COMMAND)
        self.at_command("back at the command prompt after the cast")

    def letter(self) -> int:
        """The bought item's pack letter."""
        return ord("A") + self.bought

    def home(self) -> None:
        item = self.pack()[self.bought]
        count = self.pack().count(item)
        self.walk_in(HOME_DOOR)
        self.expect("the Home's menu", lambda: "D)ep R)et Q)uit" in self.text())
        self.press(ord("D"))
        self.expect("the deposit prompt", lambda: "Which item?" in self.text())
        self.press(self.letter())
        self.settle()
        self.expect("deposited", lambda: self.pack().count(item) == count - 1)
        self.press(ord("R"))
        self.expect("the retrieve prompt", lambda: "Which?" in self.text())
        self.press(ord("A"))
        self.settle()
        self.expect("retrieved", lambda: self.pack().count(item) == count and "D)ep R)et Q)uit" in self.text())
        self.bought = self.pack().index(item)
        self.press(ord("Q"))
        self.at_command("out of the Home")

    def drop_pickup(self) -> None:
        item = self.pack()[self.bought]
        count = self.pack().count(item)
        self.press(ord("D"))
        self.expect("the drop prompt", lambda: "Drop which" in self.text())
        self.press(self.letter())
        self.at_command("dropped")
        self.expect("the pack without it", lambda: self.pack().count(item) == count - 1)
        self.press(ord("G"))
        self.at_command("picked up")
        self.expect("the pack with it again", lambda: self.pack().count(item) == count)
        self.press(ord("S"))
        self.at_command("a search, and play goes on")

    def ego_shot(self) -> None:
        """A Short Bow wielded, ten Arrows of Slay Evil, and a townsperson
        put SHOT_RANGE open squares away in a straight line, asleep and with
        200 HP: shots until one hits (``rf_roll_damage``, the ego's
        trampoline), and play goes on."""
        abi = self.abi
        # Worn through the Wear prompt, so the game's equip-time weapon cache
        # has it, +20 to-hit on it and the arrows (3 skill a point): seeded
        # in the weapon slot, a level 1 Mage's ten shots all missed on the
        # BBC (2026-11-15).
        bow = self.pack().index(FI_EMPTY)
        self.seed_slot(bow, (ITEM_SLOT_SHORT_BOW, 1, 0, SHOT_TOHIT, 0, 0, IF_KNOWN, ITEM_PAGE_SHORT_BOW))
        self.press(ord("W"))
        self.expect("the wear prompt", lambda: "Wear which item" in self.text())
        self.press(ord("?"))   # its letters count the wearable items alone
        letter = next((m.group(1) for row in self.obs.rows if (m := re.search(r"\b([a-v])\) .*Short Bow", row))), None)
        self.expect("the bow in the wear list", lambda: letter is not None)
        self.press(ord(letter.upper()))   # type: ignore[union-attr]
        self.settle()
        self.expect(
            "the bow wielded",
            lambda: self.peek(self.sym("inv_item_id") + EQUIP_WEAPON, 1)[0] == ITEM_SLOT_SHORT_BOW
            and (self.peek(self.sym("inv_ego") + EQUIP_WEAPON, 1)[0] & ITEM_PAGE_BIT) == ITEM_PAGE_SHORT_BOW,
        )
        slot = self.pack().index(FI_EMPTY)
        self.seed_slot(
            slot,
            (ITEM_SLOT_ARROW, 10, 0, SHOT_TOHIT, 0, 0, IF_KNOWN, ITEM_PAGE_ARROW | EGO_ARROW_SLAY_EVIL),
        )
        cols = abi.hal_layout_map_cols
        px, py = STREET   # out in the street: the Home's step left it on the doorway
        self._set_player_pos(px, py)
        tiles = read_map(self.game)
        street = tiles[py * cols + px] >> 4
        line = next(((dx, dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))
                     if all(tiles[(py + dy * n) * cols + px + dx * n] >> 4 == street
                            for n in range(1, SHOT_RANGE + 1))), None)
        self.expect("a straight street to shoot along", lambda: line is not None)
        target = (px + line[0] * SHOT_RANGE, py + line[1] * SHOT_RANGE)   # type: ignore[index]
        table, size = self.sym("monster_table"), abi.MONSTER_ENTRY_SIZE
        records = self.peek(table, size * abi.MAX_MONSTERS)
        # The townsperson with the least armour: the BBC's Mean-Looking
        # Mercenary (AC 20) took ten misses running from a level 1 Mage.
        ac = self.peek(self.sym("cr_ac"), 256)
        present = [i for i in range(abi.MAX_MONSTERS) if records[i * size + MX_TYPE] != 0xFF]
        town = min(present, key=lambda i: ac[records[i * size + MX_TYPE]], default=None)
        self.expect("a townsperson to shoot at", lambda: town is not None)
        record = table + town * size   # type: ignore[operator]
        hit = False
        for _ in range(SHOTS):
            if self.game.port.platform == "cpm":
                old = self.peek(record + MX_X, 2)
                if (old[0], old[1]) != target and 0 <= old[0] < cols and 0 <= old[1] < abi.hal_layout_map_rows:
                    old_addr = abi.MAP_BASE + old[1] * cols + old[0]
                    self.poke(old_addr, bytes([self.peek(old_addr, 1)[0] & ~abi.FLAG_OCCUPIED]))
                tgt_addr = abi.MAP_BASE + target[1] * cols + target[0]
                self.poke(tgt_addr, bytes([self.peek(tgt_addr, 1)[0] | abi.FLAG_OCCUPIED]))
            self.poke(record + MX_X, bytes(target))
            self.poke(record + MX_HP_LO, bytes([200, 0]))
            self.poke(record + MX_SLEEP, b"\xff")
            self.press(KEY_FIRE)
            self.expect("the fire prompt asks a direction", lambda: self.obs.mode == Mode.DIRECTION)
            self.press(DIRS[line])   # type: ignore[index]
            self.settle()
            self.expect("play goes on after the shot", lambda: self.obs.mode == Mode.COMMAND)
            hp = self.peek(record + MX_HP_LO, 2)
            if hp[0] | hp[1] << 8 < 200:
                hit = True
                break
        self.expect("an ego arrow hit the townsperson", lambda: hit)

    def legal(self) -> None:
        self.press(ord("?"))
        self.expect("the Help screen lists L:License",
                    lambda: "Command Reference" in self.text()
                    and ("L:License" in self.text() or "[L] License" in self.text()))
        self.press(ord("L"))
        self.expect("the legal viewer menu", lambda: "License & Source" in self.text())
        self.press(ord("1"))
        self.expect("the streamed LICENSE notice", lambda: "MORIA8 LICENSE NOTICE" in self.text())
        self.press(ord("Q"))
        self.expect("back at the legal menu from LICENSE", lambda: "License & Source" in self.text())
        self.press(ord("2"))
        self.expect("the streamed SOURCE-OFFER notice", lambda: "MORIA8 SOURCE OFFER" in self.text())
        self.press(ord("Q"))
        self.expect("back at the legal menu from SOURCE-OFFER", lambda: "License & Source" in self.text())
        self.press(ord("Q"))
        self.expect("Help restored after the legal viewer", lambda: "Command Reference" in self.text())
        self.press(ord("Q"))
        self.at_command("back at the command prompt after Help")

    def run(self) -> None:
        self.chargen()
        self.store_buy()
        self.second_book()
        self.home()
        self.drop_pickup()
        self.ego_shot()
        self.legal()


def tour(target: str, out: Path) -> dict[str, object]:
    port = PORTS[target]
    worker = Worker(out, build=Build.shipping(port))
    result: dict[str, object] = {"target": target, "passed": False, "steps": []}
    try:
        trip = Tour(worker, worker.start_at_title())
        try:
            trip.run()
            result["passed"] = True
        except TourFailed as failed:
            result["failure"] = str(failed)
        except GameFault as fault:
            result["failure"] = f"{fault.kind}: {fault.detail}"
        result["steps"] = trip.steps
    except Exception as exc:   # the emulator would not start or answer
        result["failure"] = f"error: {exc!r}"
    finally:
        worker.stop()
    return result


def main(argv: list[str] | None = None) -> int:
    args = argv if argv is not None else sys.argv[1:]
    target, out = args[0], Path(args[1]).resolve()
    out.mkdir(parents=True, exist_ok=True)
    result = tour(target, out)
    (out / "tour.json").write_text(json.dumps(result, indent=1))
    print(json.dumps(result, indent=1))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
