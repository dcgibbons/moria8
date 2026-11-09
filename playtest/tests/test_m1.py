import dataclasses
import struct
import unittest

from moria_playtest import abi as abimod, knowledge
from moria_playtest.auditor import Auditor
from moria_playtest.brain import (GEAR_TRIP_GOLD, GEAR_TRIP_WAIT, HUNT_HP, KEY_BASH, STUCK_STEPS, FOOD_MAX, FOOD_PER_VISIT, KEY_AUTOREST, KEY_REFUEL, KEY_RETURN, KEY_SEARCH, KEY_WEAR,
                                  LIGHT_RESERVE, DISARM_TRIES, KEY_DISARM, KEY_THROW, REFUEL_AT, RESTOCK_HOPS,
                                  Brain)
from moria_playtest.game import KEY_RUNSTOP, KEY_SPACE, Mode, Observation
from moria_playtest.goals import GOALS, required
from moria_playtest.screen import decode_rows
from moria_playtest.view import DIRS, TYPE_TRAP, UNKNOWN, WALL, Creature, View

from test_game import ABI as BASE_ABI, screen_bytes

ABI = abimod.Abi(labels={**BASE_ABI.labels, "zp_view_x": 0x60, "zp_view_y": 0x61},
                 consts=BASE_ABI.consts, all_symbols={})
COLS, ROWS = 80, 48


def command_obs(pos=(10, 5), hp=21, mhp=21, sp=0xF2, view=(0, 0), rows=None,
                monsters=(), dlvl=0, clvl=1) -> Observation:
    zp = bytearray(256)
    zp[0x2B], zp[0x2C] = pos
    zp[0x2D:0x2F] = struct.pack("<h", hp)
    zp[0x2F:0x31] = struct.pack("<h", mhp)
    zp[0x33], zp[0x34] = clvl, dlvl
    zp[0x60], zp[0x61] = view
    table = bytearray([0xFF] * 384)
    for slot, (mx, my) in enumerate(monsters):
        table[slot * 12:slot * 12 + 3] = bytes([mx, my, 1])
    # Search mode on, the bot's state while moving about (M5b); off when hurt,
    # as the bot keeps it (M6).
    search = "Search*" if hp >= HUNT_HP * mhp else "       "
    screen_rows = {21: f"bot Half-Troll  {search}     LV:1  DL:{dlvl}",
                   23: f"HP:{hp}/{mhp}  MP:0/0   AC:4  AU:277   Full"}
    col, row = pos[0] - view[0] + 1, pos[1] - view[1] + 2
    screen_rows[row] = " " * col + "@"
    screen_rows.update(rows or {})
    screen = screen_bytes(screen_rows)
    obs = Observation(1, 0x10B9, sp, 0x36, 0x1181, 4, bytes(zp), bytes(111), bytes(table),
                      screen, decode_rows(screen), abi=ABI)
    obs.mode, obs.stage = Mode.COMMAND, "command"
    return obs


def floor_tiles(occupied=()) -> bytearray:
    tiles = bytearray([0x0C] * (COLS * ROWS))   # floor, lit + visited
    for x, y in occupied:
        tiles[y * COLS + x] |= 0x01
    return tiles


def town_view(pos, stairs, monsters=frozenset(), walls=(), dlvl=0, stairs_type=0x9) -> View:
    types = [0] * (COLS * ROWS)
    for x, y in walls:
        types[y * COLS + x] = WALL
    types[stairs[1] * COLS + stairs[0]] = stairs_type
    return View(COLS, ROWS, types, pos, dlvl, {m: Creature("k", 1) for m in monsters})


def prepared(brain: Brain) -> Brain:
    """A character the readiness rules let stay below DL2 (brain.prepared):
    two cure potions and Word of Recall (fixtures give it the HP)."""
    brain.clw, brain.recall = max(brain.clw, 2), max(brain.recall, 1)
    return brain


class ViewBrainTest(unittest.TestCase):
    def test_descends_when_on_stairs(self) -> None:
        brain = Brain(GOALS["enter_dungeon"])
        decision = brain.decide(command_obs(), town_view((5, 5), (5, 5)))
        self.assertEqual((decision.key, decision.layer), (ord(">"), "descend"))

    def test_walks_toward_stairs_around_a_creature(self) -> None:
        brain = Brain(GOALS["enter_dungeon"])
        decision = brain.decide(command_obs(), town_view((5, 5), (7, 5), monsters={(6, 5)}))
        self.assertIn(decision.key, (DIRS[(1, -1)], DIRS[(1, 1)]))

    def test_never_paths_into_a_breeding_nest(self) -> None:
        """M5b round 9: descend pushed through a Blue Worm nest to the stairs
        past it, fighting worms that bred faster than they died."""
        ring = {(20 + dx, 20 + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1)} - {(20, 20)}
        brain = prepared(Brain(GOALS["reach_dl8"]))
        brain.food = 5
        obs = command_obs(pos=(5, 5), dlvl=2, clvl=10, hp=90, mhp=90)
        view = town_view((5, 5), (20, 20), dlvl=2, monsters=ring)    # Kobolds round the stairs
        self.assertIsNotNone(brain.descend(obs, view))
        view.creatures = {p: Creature("w", 4) for p in ring}         # Blue Worm masses
        self.assertIsNone(brain.descend(obs, view))

    def test_unknown_tiles_are_not_walkable(self) -> None:
        view = town_view((5, 5), (9, 5))
        view.types[5 * COLS + 6] = UNKNOWN
        self.assertFalse(view.passable(6, 5, avoid_monsters=True))

    def test_prompt_layer(self) -> None:
        brain = Brain(GOALS["enter_dungeon"])
        for mode, key in ((Mode.DISMISS, 0x20), (Mode.UNKNOWN, 0x03), (Mode.DEATH, 0x20)):
            obs = dataclasses.replace(command_obs(), mode=mode, stage="")
            self.assertEqual(brain.decide(obs, None).key, key)


class BrainM2Test(unittest.TestCase):
    def obs(self, hp=21, mhp=21, msg="", dlvl=1, pos=(5, 5)):
        o = command_obs(hp=hp, mhp=mhp, dlvl=dlvl, pos=pos)
        o.rows[0] = msg.ljust(40)
        return o

    def test_frontier_and_search_spots(self) -> None:
        view = town_view((5, 5), (60, 40), dlvl=1)
        view.types = [UNKNOWN] * (COLS * ROWS)
        for x in range(3, 8):
            view.types[5 * COLS + x] = 0x0          # a short corridor of floor
        view.types[5 * COLS + 8] = WALL               # wall, unknown beyond
        self.assertIn((3, 5), view.frontier())
        self.assertEqual(view.search_spots(set()) & {(7, 5)}, {(7, 5)})

    def test_known_trap_is_never_a_destination(self) -> None:
        view = town_view((5, 5), (60, 40), dlvl=1)
        view.types = [UNKNOWN] * (COLS * ROWS)
        for x in range(3, 8):
            view.types[5 * COLS + x] = 0x0
        view.types[5 * COLS + 3] = TYPE_TRAP          # revealed trap at the corridor's open end
        view.types[5 * COLS + 8] = WALL
        view.types[4 * COLS + 3] = WALL
        self.assertNotIn((3, 5), view.frontier())
        self.assertNotIn((3, 5), view.search_spots(set()))

    def test_keep_clear_refuses_tiles_next_to_creatures(self) -> None:
        view = town_view((5, 5), (5, 9), dlvl=1, monsters={(6, 6)})
        step = view.step_toward({(5, 9)}, avoid_monsters=True, keep_clear=True)
        self.assertNotIn((5 + step[0], 5 + step[1]), {(5, 6), (6, 5), (6, 6), (6, 7), (5, 7), (7, 5)})

    def test_hurt_with_creature_in_view_runs_for_stairs(self) -> None:
        brain = Brain(GOALS["reach_clvl2"])
        view = town_view((5, 5), (5, 2), dlvl=1, monsters={(12, 12)}, stairs_type=0xA)
        decision = brain.decide(self.obs(hp=12), view)
        self.assertEqual((decision.layer, decision.key), ("retreat", DIRS[(0, -1)]))

    def test_first_strike_waits_for_contact(self) -> None:
        brain = Brain(GOALS["reach_clvl2"])
        brain.food, brain.clw = 3, 5                         # supplied: not a food or potion test (round 25)
        view = town_view((5, 5), (40, 40), dlvl=1, monsters={(7, 5)})
        # 40 HP: a character sturdy enough to take a Kobold on.
        self.assertEqual(brain.decide(self.obs(hp=40, mhp=40), view).reason,
                         "wait for it to step into contact: first strike")

    def test_unseen_attacker_stops_resting(self) -> None:
        brain = Brain(GOALS["reach_clvl2"])
        view = town_view((5, 5), (5, 3), dlvl=1, stairs_type=0xA)
        decision = brain.decide(self.obs(hp=15, msg="the Kobold hits you."), view)
        self.assertEqual(decision.layer, "retreat")

    def test_no_fighting_in_town(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        decision = brain.decide(self.obs(dlvl=0), town_view((5, 5), (9, 5), monsters={(6, 5)}))
        self.assertNotEqual(decision.layer, "fight")

    def test_no_food_stops_eating_until_a_pickup(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        view = town_view((5, 5), (40, 40), dlvl=1)

        def hungry(msg: str) -> Observation:
            o = self.obs(msg=msg)
            o.rows[23] = "HP:21/21  MP:0/0   AC:4  AU:277   Hungry"
            return o

        self.assertEqual(brain.decide(hungry(""), view).layer, "eat")
        self.assertNotEqual(brain.decide(hungry("You have no food."), view).layer, "eat")
        self.assertNotEqual(brain.decide(hungry(""), view).layer, "eat")
        self.assertEqual(brain.decide(hungry("You picked up a Ration of Food."), view).layer, "eat")

    def store_obs(self, stage: str, rows: dict[int, str]) -> Observation:
        o = self.obs(dlvl=0)
        o.rows = [" " * 40] * 25
        for row, text in rows.items():
            o.rows[row] = text.ljust(40)
        o.mode, o.stage = Mode.STORE, stage
        return o

    def test_store_buys_food_then_leaves(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        stock = {3: " a) Iron Spike                 1 GP", 5: " c) Ration of Food             3 GP",
                 7: " e) Ration of Food             3 GP", 19: " B)uy  S)ell  Q)uit"}
        keys = [brain.decide(self.store_obs("menu", stock), None).key,
                brain.decide(self.store_obs("buy_which", stock), None).key,
                brain.decide(self.store_obs("buy_confirm", stock), None).key]
        self.assertEqual(keys, [ord("B"), ord("C"), ord("Y")])
        sold = {**stock, 5: " c)"}
        self.assertEqual(brain.decide(self.store_obs("menu", sold), None).key, ord("B"))
        self.assertEqual(brain.decide(self.store_obs("buy_which", sold), None).key, ord("E"))
        self.assertEqual(brain.decide(self.store_obs("menu", {3: stock[3], 19: stock[19]}), None).key, ord("Q"))
        self.assertTrue(brain.shopped)

    def test_store_buys_from_a_stack(self) -> None:
        # A store stack shows its count first, as the pack does (stores
        # stack since 2026-10-25, Umoria storeCarryItem).
        brain = Brain(GOALS["reach_dl2"])
        stock = {5: " c) 5 Ration of Food           3 GP", 19: " B)uy  S)ell  Q)uit"}
        self.assertEqual(brain.decide(self.store_obs("menu", stock), None).key, ord("B"))
        self.assertEqual(brain.decide(self.store_obs("buy_which", stock), None).key, ord("C"))

    def test_store_never_pays_dear_for_ammunition(self) -> None:
        # 2026-11-04: a Human Warrior paid 407 of 473 starting gold for a
        # Sling and two Rock (+1,+1), and had none left for potions.
        brain = Brain(GOALS["reach_dl2"])
        brain.launcher, brain.ammo, brain.food, brain.oil, brain.torches = "Sling", 0, 20, 30, 5
        dear = {3: " a) Rock (+1,+1)              203 GP", 19: " B)uy  S)ell  Q)uit"}
        self.assertEqual(brain.decide(self.store_obs("menu", dear), None).key, ord("Q"))
        brain = Brain(GOALS["reach_dl2"])
        brain.launcher, brain.ammo, brain.food, brain.oil, brain.torches = "Sling", 0, 20, 30, 5
        cheap = {**dear, 4: " b) 20 Rock                    1 GP"}
        self.assertEqual(brain.decide(self.store_obs("menu", cheap), None).key, ord("B"))
        self.assertEqual(brain.decide(self.store_obs("buy_which", cheap), None).key, ord("B"))

    def test_store_message_ends_shopping(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        rows = {5: " c) Ration of Food             3 GP", 19: " B)uy  S)ell  Q)uit"}
        self.assertEqual(brain.decide(self.store_obs("message", rows), None).key, KEY_SPACE)
        self.assertEqual(brain.decide(self.store_obs("menu", rows), None).key, ord("Q"))

    def test_town_walks_to_the_general_store_once(self) -> None:
        brain = Brain(GOALS["enter_dungeon"])
        view = town_view((5, 8), (30, 8))
        view.stores = [(5, 6)]
        view.types[6 * COLS + 5] = 0x7                  # store entrance
        decision = brain.decide(self.obs(dlvl=0, pos=(5, 8)), view)
        self.assertEqual((decision.layer, decision.key), ("shop", DIRS[(0, -1)]))
        brain.shopped = True
        self.assertEqual(brain.decide(self.obs(dlvl=0, pos=(5, 8)), view).layer, "descend")

    def test_out_of_food_heads_for_town(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        view = town_view((5, 5), (5, 2), dlvl=1, stairs_type=0xA)
        o = self.obs(msg="You have no food.")
        o.rows[23] = "HP:21/21  MP:0/0   AC:4  AU:277   Weak"
        decision = brain.decide(o, view)
        self.assertEqual((decision.layer, decision.key), ("resupply", DIRS[(0, -1)]))

    def test_paths_detour_around_a_known_trap_but_cross_it_if_needed(self) -> None:
        view = town_view((5, 5), (40, 40), dlvl=1)
        view.types[5 * COLS + 6] = TYPE_TRAP
        self.assertNotEqual(view.step_toward({(7, 5)}, avoid_monsters=True), (1, 0))
        view.types = [WALL] * (COLS * ROWS)               # now a walled one-wide corridor
        for x in (5, 6, 7):
            view.types[5 * COLS + x] = TYPE_TRAP if x == 6 else 0x0
        self.assertEqual(view.step_toward({(7, 5)}, avoid_monsters=True), (1, 0))

    def test_explores_across_a_trap_only_when_nothing_else_is_left(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        view = town_view((5, 5), (60, 40), dlvl=1)
        view.types = [WALL] * (COLS * ROWS)
        for x in (4, 5):
            view.types[5 * COLS + x] = 0x0
        view.types[5 * COLS + 6] = TYPE_TRAP              # corridor end: unknown beyond the trap
        view.types[5 * COLS + 7] = UNKNOWN
        decision = brain.decide(self.obs(), view)
        # Round 23: across the trap, disarming it first.
        self.assertEqual((decision.layer, decision.key, brain.pending), ("explore", KEY_DISARM, DIRS[(1, 0)]))

    def test_xp_goal_never_scums_deeper(self) -> None:
        brain = Brain(GOALS["reach_clvl2"])
        brain.food, brain.clw = 3, 5                                       # supplied: not a food or potion test (round 25)
        view = town_view((5, 5), (5, 5), dlvl=1)          # standing on a down staircase
        brain.level.scum = True
        self.assertNotEqual(brain.decide(self.obs(), view).key, ord(">"))


class LookFirstTest(unittest.TestCase):
    """M3 round 1 (§14.3): unfamiliar glyphs are looked at, or learned the hard way."""

    def obs(self, msg: str = "", pos=(5, 5)):
        o = command_obs(dlvl=4, pos=pos)
        o.rows[0] = "Direction?".ljust(40) if msg else " " * 40
        o.rows[1] = msg.ljust(40)
        return o

    def view(self, unknown, pos=(5, 5), cornered=False):
        v = town_view(pos, (60, 40), dlvl=4)
        v.unknown = dict(unknown)
        if cornered:   # nowhere to step away to: creeping coins are fought (round 45)
            v.types = [WALL] * (COLS * ROWS)
            for x, y in [pos, (5, 5), *unknown]:
                v.types[y * COLS + x] = 0x0
        return v

    def test_glyph_classes(self) -> None:
        from moria_playtest.view import is_unknown_glyph
        self.assertTrue(all(is_unknown_glyph(c) for c in "$,!?=-"))
        self.assertFalse(any(is_unknown_glyph(c) for c in ".#'+<>:%· @k3"))

    def test_creature_names_are_player_knowledge(self) -> None:
        from moria_playtest import knowledge
        self.assertEqual(knowledge.creature_levels()["Creeping Copper Coins"], 4)
        self.assertNotIn("Ration of Food", knowledge.creature_levels())
        self.assertEqual(knowledge.attacker("the Creeping Copper Coins poisons you."),
                         "Creeping Copper Coins")
        self.assertIsNone(knowledge.attacker("the Kobold dies."))

    def test_aligned_glyph_is_looked_at_and_a_creature_name_makes_it_a_creature(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        decision = brain.decide(self.obs(), self.view({(8, 5): "$"}))
        self.assertEqual((decision.key, decision.layer), (ord("X"), "look"))
        self.assertEqual(brain.pending, DIRS[(1, 0)])
        view = self.view({(8, 5): "$"})
        brain.decide(self.obs("You see a Creeping Copper Coins."), view)
        self.assertEqual(view.creatures[(8, 5)], Creature("$", 4))
        self.assertNotIn((8, 5), view.unknown)

    def test_an_item_name_makes_the_square_walkable(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        brain.decide(self.obs(), self.view({(8, 5): "!"}))
        view = self.view({(8, 5): "!"})
        brain.decide(self.obs("You see a Flask of Oil."), view)
        self.assertNotIn((8, 5), view.creatures)
        self.assertTrue(view.passable(8, 5, avoid_monsters=True))

    def test_unaligned_glyph_is_not_looked_at_and_paths_go_around_it(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        view = self.view({(7, 6): "$"})
        self.assertNotEqual(brain.decide(self.obs(), view).layer, "look")
        step = view.step_toward({(9, 5)}, avoid_monsters=True)
        self.assertNotIn((5 + step[0], 5 + step[1]), {(6, 5), (6, 6), (6, 7)})

    def test_attacked_by_an_adjacent_unknown_glyph_means_it_is_that_creature(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        view = self.view({(6, 6): "$"}, cornered=True)
        brain.level.looked.add(((5, 5), (6, 6)))      # already looked; it was dark
        o = self.obs("the Creeping Copper Coins poisons you.")
        o.rows[0] = " " * 40
        decision = brain.decide(o, view)
        self.assertIn((6, 6), view.creatures)
        self.assertEqual((decision.layer, decision.key), ("fight", DIRS[(1, 1)]))

    def test_an_unseen_attacker_is_never_pinned_on_an_item_glyph(self) -> None:
        """Round 20: '/' is no creature's glyph; a weapon lay next to the
        player when an invisible attacker struck (seed 1014)."""
        brain = Brain(GOALS["reach_dl2"])
        view = self.view({(6, 6): "/"})
        brain.level.looked.add(((5, 5), (6, 6)))
        o = self.obs("the Poltergeist hits you.")
        o.rows[0] = " " * 40
        brain.decide(o, view)
        self.assertNotIn((6, 6), view.creatures)

    def test_an_attacker_is_only_pinned_on_its_own_glyph(self) -> None:
        """Review: a dropped Ration (',', also a mushroom glyph) next to the
        player was pinned as the Kobold that hit them, and became a wall."""
        brain = Brain(GOALS["reach_dl2"])
        view = self.view({(6, 6): ","})
        brain.level.looked.add(((5, 5), (6, 6)))
        o = self.obs("the Kobold hits you.")
        o.rows[0] = " " * 40
        brain.decide(o, view)
        self.assertNotIn((6, 6), view.creatures)
        self.assertEqual(brain.level.stationary, {})

    def test_a_fight_that_lands_on_the_target_drops_the_identification(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        brain.decide(self.obs(), self.view({}))                       # enter the level
        brain.level.identified[((6, 5), "$")] = ("creature", "Creeping Copper Coins")
        decision = brain.decide(self.obs(), self.view({(6, 5): "$"}, cornered=True))
        self.assertEqual(decision.layer, "fight")
        brain.decide(self.obs(pos=(6, 5)), self.view({}, pos=(6, 5)))   # walked onto it
        view = self.view({(6, 5): "$"}, cornered=True)
        brain.decide(self.obs(), view)
        self.assertNotIn((6, 5), view.creatures)

    def test_an_unknown_glyph_in_the_only_exit_does_not_trap_the_player(self) -> None:
        view = self.view({(7, 5): "/"})
        view.types = [WALL] * (COLS * ROWS)
        for x in range(4, 11):
            view.types[5 * COLS + x] = 0x0               # one-wide corridor through the item
        self.assertEqual(view.step_toward({(10, 5)}, avoid_monsters=True), (1, 0))

    def test_each_glyph_is_looked_at_once_from_a_spot(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        brain.decide(self.obs(), self.view({(8, 5): "$"}))
        self.assertNotEqual(brain.decide(self.obs(), self.view({(8, 5): "$"})).layer, "look")


class ReadinessTest(unittest.TestCase):
    """M3 round 2 (§14.3): DL n only at character level >= n."""

    def test_underleveled_character_does_not_go_deeper(self) -> None:
        brain = Brain(GOALS["reach_dl2"].__class__("reach_dl5", "", lambda o: o.dlvl >= 5, target_dlvl=5))
        view = town_view((5, 5), (5, 5), dlvl=1)            # on a down staircase
        view.types[5 * COLS + 20] = 0xA                     # a way up exists
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=1, clvl=1), view)
        self.assertNotEqual(decision.key, ord(">"))

    def test_the_last_step_of_a_depth_goal_is_always_taken(self) -> None:
        brain = Brain(GOALS["reach_dl2"])                    # target DL2
        brain.food = 0
        view = town_view((5, 5), (5, 5), dlvl=1)            # on a down staircase
        view.types[5 * COLS + 20] = 0xA
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=1, clvl=1), view)
        self.assertEqual((decision.layer, decision.key), ("descend", ord(">")))

    def test_ready_character_goes_deeper(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        brain.food = 3                                       # well supplied
        view = town_view((5, 5), (5, 5), dlvl=1)
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=1, clvl=2), view)
        self.assertEqual((decision.key, decision.layer), (ord(">"), "descend"))

    def test_one_level_of_margin_below_dl1(self) -> None:
        """Round 18: every M3 death was at exactly the minimum level for its
        depth; DL n (n >= 2) needs margin (round 24: DL3 needs level 5)."""
        brain = prepared(Brain(GOALS["clvl5"]))
        brain.food = 3
        view = town_view((5, 5), (5, 5), dlvl=2)            # on a down staircase
        view.types[5 * COLS + 20] = 0xA
        # HP for two DL3 spells (M5a SpellReadinessTest), so the level decides.
        self.assertNotEqual(brain.decide(command_obs(pos=(5, 5), dlvl=2, clvl=4, hp=60, mhp=60), view).key, ord(">"))
        self.assertEqual(brain.decide(command_obs(pos=(5, 5), dlvl=2, clvl=5, hp=60, mhp=60), view).key, ord(">"))
        town = town_view((5, 5), (5, 5), dlvl=0)
        brain.shopped = True
        brain.decide(command_obs(pos=(5, 5), dlvl=0, clvl=1), town)   # arrived: the armour list first
        brain.equip_checked = True
        self.assertEqual(brain.decide(command_obs(pos=(5, 5), dlvl=0, clvl=1), town).key, ord(">"))

    def test_two_levels_of_margin_from_dl3(self) -> None:
        """Round 24: after round 18, the deaths sat at the new minimum (DL3
        at level 4); DL n (n >= 3) needs character level n + 2."""
        from moria_playtest.brain import ready_level
        self.assertEqual([ready_level(n) for n in range(1, 6)], [1, 3, 5, 6, 7])
        self.assertEqual([ready_level(n, 0) for n in range(1, 6)], [1, 2, 3, 4, 5])   # depth goals

    def test_underleveled_depth_goal_hunts_for_experience(self) -> None:
        brain = Brain(GOALS["reach_dl2"].__class__("reach_dl5", "", lambda o: o.dlvl >= 5, target_dlvl=5))                    # depth goal: want_xp is False
        brain.food, brain.clw = 3, 5                                       # supplied: not a food or potion test (round 25)
        view = town_view((5, 5), (40, 40), dlvl=1, monsters={(9, 5)})
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=1, clvl=1, hp=40, mhp=40), view)   # sturdy (M5b)
        self.assertEqual(decision.layer, "hunt")


class ArrivalClimbTest(unittest.TestCase):
    """M5b round 20: a crowd escape took a level-3 Paladin down to DL2,
    where it stayed and died to a Novice Priest (seed 1019)."""

    def test_climbs_back_at_once_from_a_depth_it_is_not_ready_for(self) -> None:
        brain = Brain(GOALS["reach_dl8"])                      # DL2 wants level 4 (margin 3)
        brain.food, brain.recall, brain.torches, brain.oil, brain.clw = 6, 2, 2, 3, 5
        on_stairs = town_view((5, 5), (5, 5), dlvl=2, stairs_type=0xA)
        decision = brain.resupply(command_obs(pos=(5, 5), dlvl=2, clvl=3, hp=30, mhp=30), on_stairs)
        self.assertEqual((decision.key, decision.reason), (ord("<"), "DL2 too deep for level 3: go up"))
        away = town_view((5, 5), (9, 5), dlvl=2, stairs_type=0xA)
        self.assertIsNone(brain.resupply(command_obs(pos=(5, 5), dlvl=2, clvl=3, hp=30, mhp=30), away))
        self.assertIsNone(brain.resupply(command_obs(pos=(5, 5), dlvl=2, clvl=4, hp=30, mhp=30), on_stairs))


class DropJunkTest(unittest.TestCase):
    """M5b round 29: worn-out gear filled the pack; every purchase failed and
    two Dwarf Priests hopped between town and DL1 for 4,000 steps."""

    @staticmethod
    def item(stage: str, rows: dict[int, str]):
        o = command_obs(rows=rows)
        o.mode, o.stage = Mode.ITEM, stage
        return o

    def test_drops_the_first_item_not_kept(self) -> None:
        brain = Brain(GOALS["reach_dl8"])
        view = town_view((5, 5), (40, 40), dlvl=0)
        o = command_obs(pos=(5, 5), dlvl=0, clvl=5, rows={0: "Your pack is full."})
        self.assertEqual(brain.decide(o, view).key, ord("D"))
        self.assertEqual(brain.decide(self.item("which", {0: "Drop which item (a-v)?"}), None).key, ord("?"))
        pack = {0: "Inventory", 2: " a) 5 Ration of Food", 3: " b) Holy Book of Prayers Beginners",
                4: " c) Wooden Torch (0 turns)", 5: " d) Soft Leather Armor [8,+0]", 6: " e) Dagger (1d4)"}
        self.assertEqual(brain.decide(self.item("list", pack), None).key, ord("C"))   # the burnt-out torch
        brain.pack_full, brain.dropping, brain.listed = True, True, True
        pack[4] = " c) Wooden Torch (134 turns)"
        self.assertEqual(brain.decide(self.item("list", pack), None).key, ord("D"))   # then replaced armour
        self.assertFalse(brain.pack_full)

    def test_only_the_launcher_carried_and_its_ammunition_are_kept(self) -> None:
        """M8, 2026-11-02: a level-25 Dwarf's pack held three launchers,
        arrows and bolts, empty lanterns and burnt-out torches; one item a
        town trip was dropped and every purchase failed on the full pack."""
        brain = Brain(GOALS["deep"])
        brain.credit("Heavy Crossbow (+1,+1)", 1)
        pack = {0: "Inventory", 2: " a) 11 Arrow", 3: " b) Long Bow (+2,+2)", 4: " c) Heavy Crossbow (+1,+1)",
                5: " d) 45 Bolt", 6: " e) Brass Lantern (0 turns)", 7: " f) 3 Wooden Torch (134 turns)"}
        brain.pack_full, brain.dropping, brain.listed = True, True, True
        dropped = []
        for _ in range(4):
            decision = brain.decide(self.item("list", pack), None)
            if decision.key == KEY_RUNSTOP:
                break
            letter = chr(decision.key).lower()
            dropped.append(letter)
            brain.credit(next(r for r in pack.values() if r.startswith(f" {letter})"))[4:], -1)
            pack = {k: v for k, v in pack.items() if not v.startswith(f" {letter})")}
            self.assertEqual(brain.more_junk, len(dropped) < 3)   # more to drop after the first two
            brain.dropping, brain.listed = True, True
        self.assertEqual(dropped, ["a", "b", "e"])          # arrows, the spare bow, the empty lantern
        self.assertEqual(brain.launcher, "Heavy Crossbow")  # dropping the bow kept the crossbow

    def test_nothing_to_spare_is_not_retried_at_once(self) -> None:
        brain = Brain(GOALS["reach_dl8"])
        brain.pack_full, brain.dropping, brain.listed = True, True, True
        keep = {0: "Inventory", 2: " a) 5 Ration of Food", 3: " b) Potion of Cure Light Wounds"}
        o = self.item("list", keep)
        o.step = 1000
        self.assertEqual(brain.decide(o, None).key, KEY_RUNSTOP)
        self.assertEqual(brain.drop_after, 1000 + 500)


class FoodSupplyTest(unittest.TestCase):
    """M3 round 3 (§14.3): count food as a player does; resupply before running out."""

    def test_eating_down_to_the_reserve_heads_for_town(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        brain.food = 1                                       # DL1-2 keep one ration (M5b round 35)
        view = town_view((5, 5), (5, 2), dlvl=1, stairs_type=0xA)   # up stairs north
        o = command_obs(pos=(5, 5), dlvl=1, clvl=2)
        o.rows[0] = "You eat the Ration of Food. Delicious!".ljust(40)
        decision = brain.decide(o, view)
        self.assertEqual(brain.food, 0)
        self.assertEqual((decision.layer, decision.key), ("resupply", DIRS[(0, -1)]))

    def test_low_food_blocks_going_deeper_in_the_dungeon_but_not_from_town(self) -> None:
        brain = Brain(GOALS["reach_dl2"].__class__("reach_dl5", "", lambda o: o.dlvl >= 5, target_dlvl=5))
        brain.food = 1
        on_stairs = town_view((5, 5), (5, 5), dlvl=1)
        on_stairs.types[5 * COLS + 20] = 0xA                # a way up exists
        self.assertNotEqual(brain.decide(command_obs(pos=(5, 5), dlvl=1, clvl=2), on_stairs).key, ord(">"))
        town = town_view((5, 5), (5, 5), dlvl=0)
        brain.shopped = True
        brain.decide(command_obs(pos=(5, 5), dlvl=0, clvl=2), town)   # arrived: the armour list first
        brain.equip_checked = True
        self.assertEqual(brain.decide(command_obs(pos=(5, 5), dlvl=0, clvl=2), town).key, ord(">"))

    def test_purchases_count_and_a_refused_one_is_undone(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        brain.food = 1                                      # one ration carried
        menu = {5: " c) Slime Mold                 2 GP", 19: " B)uy  S)ell  Q)uit"}
        store = BrainM2Test.store_obs
        for stage in ("menu", "buy_which", "buy_confirm"):
            brain.decide(store(BrainM2Test(), stage, menu), None)
        self.assertAlmostEqual(brain.food, 1 + 1 / 3)       # a Slime Mold is a third of a ration (M4 round 42)
        brain.decide(store(BrainM2Test(), "message", {**menu, 22: " You cannot afford that."}), None)
        self.assertAlmostEqual(brain.food, 1)


class FoodDepthTest(unittest.TestCase):
    """M4 round 42: ~10 characters starved on DL3-8; the climb home is longer
    from deeper, and a Slime Mold feeds a third as long as a Ration."""

    def test_the_reserve_grows_with_depth(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        brain.food, brain.trip_dlvl = 3, 1
        self.assertFalse(brain.food_low())
        brain.trip_dlvl = 6                                  # reserve 2 + 6 // 3 = 4
        self.assertTrue(brain.food_low())

    def test_one_level_from_a_depth_goal_the_depth_reserve_does_not_send_it_up(self) -> None:
        """M4 round 70: seed 1026 climbed back from DL9 with 4 rations and
        starved in a sealed DL8 pocket."""
        brain = Brain(GOALS["reach_dl8"])
        brain.food, brain.trip_dlvl = 3, 7                   # reserve 2 + 7 // 3 = 4
        view = town_view((5, 5), (5, 5), dlvl=7, stairs_type=0xA)   # arrived on the up stairs
        view.types[10 * COLS:11 * COLS] = [UNKNOWN] * COLS   # unexplored beyond row 9
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=7, clvl=9), view)
        self.assertNotEqual(decision.key, ord("<"))
        brain.food = 1                                       # truly short of food: up it goes
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=7, clvl=9), view)
        self.assertEqual((decision.layer, decision.key), ("resupply", ord("<")))

    def test_eating_a_slime_mold_costs_a_third(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        brain.food = 2
        brain.count_food("You eat the Slime Mold. Yuck!")
        self.assertAlmostEqual(brain.food, 2 - 1 / 3)


class LightTest(unittest.TestCase):
    """M3 round 13 (§14.3): a lantern and oil, so the light never goes out."""

    STOCK = {3: " a) Iron Spike                 1 GP", 4: " b) Flask of Oil (250 turns)   12 GP",
             13: " k) Brass Lantern (250 turns)  24 GP", 19: " B)uy  S)ell  Q)uit  Gold: 265"}

    def store(self, brain, stage, rows):
        return brain.decide(BrainM2Test.store_obs(BrainM2Test(), stage, rows), None).key

    def test_buys_a_lantern_at_the_asking_price_then_oil(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        brain.shop_buys, brain.clvl = FOOD_PER_VISIT, 5   # early, the kit's torches do (M5b round 48)
        self.assertEqual(self.store(brain, "menu", self.STOCK), ord("B"))
        self.assertEqual(self.store(brain, "buy_which", self.STOCK), ord("K"))
        haggle = {**self.STOCK, 20: " Asks 24 gp.", 21: " Your offer? (Q=cancel)"}
        self.assertEqual([self.store(brain, "haggle", haggle) for _ in range(3)],
                         [ord("2"), ord("4"), KEY_RETURN])
        self.assertTrue(brain.lamp_packed)
        sold = {**self.STOCK, 13: " k)", 19: " B)uy  S)ell  Q)uit  Gold: 241"}
        self.assertEqual(self.store(brain, "menu", sold), ord("B"))
        self.assertEqual(self.store(brain, "buy_which", sold), ord("B"))

    def test_skips_what_it_cannot_afford(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        brain.shop_buys = FOOD_PER_VISIT
        # 10 gp: neither the lantern (24) nor oil (12, wanted since M4) is affordable.
        self.assertEqual(self.store(brain, "menu", {**self.STOCK, 19: " B)uy  S)ell  Q)uit  Gold: 10"}), ord("Q"))

    def test_picks_the_last_item_of_a_full_pack(self) -> None:
        """M4 seed 1006: 21 items (a-u) list down to row 21; the newest
        purchase, the oil, is last and was never found."""
        brain = Brain(GOALS["reach_dl2"])
        brain.picking, brain.oil = "Flask of Oil", 3
        listed = command_obs(pos=(5, 5), rows={1: " a) Soft Leather Armor", 21: " u) Flask of Oil"})
        listed.mode, listed.stage = Mode.ITEM, "list"
        self.assertEqual(brain.decide(listed, None).key, ord("U"))

    def test_a_lantern_still_carries_spare_torches(self) -> None:
        """M4: seed 1007's lantern ran dry, its one torch burnt out, and it
        played 3,400 steps in the dark."""
        brain = Brain(GOALS["reach_dl2"])
        brain.shop_buys, brain.lamp, brain.oil, brain.torches = FOOD_PER_VISIT, True, 3, 0   # the spares used up
        self.assertIn("Wooden Torch", brain.shopping_list())

    def test_buys_oil_to_throw_even_without_a_lantern(self) -> None:
        """M4 (§15.5): seed 1004 had no lantern, so no oil, and nothing to
        throw at the Poltergeist that kept it afraid."""
        brain = Brain(GOALS["reach_dl2"])
        brain.shop_buys, brain.torches = FOOD_PER_VISIT, 2
        self.assertIn("Flask of Oil", brain.shopping_list())

    def test_wears_the_bought_lantern_by_name(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        brain.lamp_packed = brain.shopped = True
        view = town_view((5, 5), (20, 20))
        decision = brain.decide(command_obs(pos=(5, 5)), view)
        self.assertEqual((decision.layer, decision.key), ("light", KEY_WEAR))
        prompt = command_obs(pos=(5, 5), rows={0: "Wear which item (a-b)?"})
        prompt.mode, prompt.stage = Mode.ITEM, "which"
        self.assertEqual(brain.decide(prompt, None).key, ord("?"))
        listed = command_obs(pos=(5, 5), rows={1: " a) Soft Leather Armor", 2: " b) Brass Lantern (250 turns)"})
        listed.mode, listed.stage = Mode.ITEM, "list"
        self.assertEqual(brain.decide(listed, None).key, ord("B"))
        brain.decide(command_obs(pos=(5, 5), rows={0: "You are wearing a Brass Lantern (250 tur"}), view)
        self.assertTrue(brain.lamp)

    def test_buys_torches_when_no_lantern_is_for_sale(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        brain.shop_buys, brain.torches = FOOD_PER_VISIT, 0   # the spares used up
        stock = {**self.STOCK, 13: " k) Wooden Torch                2 GP"}
        self.assertEqual(self.store(brain, "menu", stock), ord("B"))
        self.assertEqual(self.store(brain, "buy_which", stock), ord("K"))
        self.assertEqual(self.store(brain, "buy_confirm", stock), ord("Y"))
        self.assertEqual(brain.torches, 1)

    def test_refuels_before_it_burns_out_and_heads_for_town_without_oil(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        brain.lamp, brain.oil, brain.food, brain.light_left = True, 1, 3, REFUEL_AT
        brain.torches = 0                                   # no torch to fall back on
        view = town_view((5, 5), (5, 2), dlvl=1, stairs_type=0xA)
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=1, clvl=2), view)
        self.assertEqual((decision.layer, decision.key), ("light", KEY_REFUEL))
        refueled = {0: "Your lamp is refueled."}
        self.assertNotEqual(brain.decide(command_obs(pos=(5, 5), dlvl=1, clvl=2, rows=refueled), view).layer,
                            "resupply")
        brain.light_left = LIGHT_RESERVE
        brain.last_move = None   # the fixture never moves the player: not a bump (round 17)
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=1, clvl=2), view)
        self.assertEqual((decision.layer, decision.key), ("resupply", DIRS[(0, -1)]))

    def test_a_burnt_out_torch_is_replaced_by_a_spare(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        brain.torches, brain.food = 1, 3
        view = town_view((5, 5), (5, 2), dlvl=1, stairs_type=0xA)
        out = {0: "Your light has gone out."}
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=1, clvl=2, rows=out), view)
        self.assertEqual((decision.layer, decision.key), ("light", KEY_WEAR))
        self.assertEqual(brain.picking, "Wooden Torch")

    def test_the_spare_torch_is_the_one_with_the_most_turns(self) -> None:
        # M5b round 43, seed 1020: the first torch listed was burnt out, and
        # the bot explored blind for 44,000 steps.
        brain = Brain(GOALS["reach_dl2"])
        brain.torches, brain.picking, brain.listed = 2, "Wooden Torch", True
        o = command_obs(rows={0: "Wear which item? (a-c)", 2: " a) Wooden Torch (0 turns)",
                              3: " b) Wooden Torch (1 turns)", 4: " c) Wooden Torch (133 turns)"})
        self.assertEqual(brain.pick_item(o).key, ord("C"))
        brain.picking = "Wooden Torch"
        spent = command_obs(rows={0: "Wear which item? (a-a)", 2: " a) Wooden Torch (0 turns)"})
        self.assertEqual(brain.pick_item(spent).reason, "item to pick not listed: cancel")
        self.assertEqual(brain.torches, 0)

    def test_a_read_with_no_scroll_carried_zeroes_the_scrolls(self) -> None:
        """2026-11-07: with no scroll at all the read says "You have nothing
        there." and shows no list; a level-28 Rogue's count kept a Word of
        Recall it lacked and read it every 2,000 steps for a million steps."""
        brain = Brain(GOALS["reach_dl2"])
        brain.recall, brain.phase, brain.clw = 2, 1, 3
        brain.picking = "Scroll of Word of Rec"
        view = town_view((5, 5), (5, 2), dlvl=1, stairs_type=0xA)
        brain.decide(command_obs(pos=(5, 5), dlvl=1, clvl=2, rows={0: "You have nothing there."}), view)
        self.assertEqual((brain.recall, brain.phase, brain.clw, brain.picking), (0, 0, 3, None))

    def test_an_empty_light_put_on_is_dark(self) -> None:
        # M5b round 43, seed 1006: a new lantern bought beside an empty one;
        # the empty one was worn, never said "gone out", and the flasks for it
        # stayed in the pack.
        brain = Brain(GOALS["reach_dl2"])
        brain.picking, brain.listed = "Brass Lantern", True
        o = command_obs(rows={0: "Wear which item? (a-b)", 2: " a) Brass Lantern (0 turns)",
                              3: " b) Brass Lantern (250 turns)"})
        self.assertEqual(brain.pick_item(o).key, ord("B"))
        brain.track_light("You are wearing a Brass Lantern (0 turns).")
        self.assertTrue(brain.dark)
        self.assertEqual(brain.light_left, 0)
        brain.track_light("You are wearing a Wooden Torch (133 turns).")
        self.assertFalse(brain.dark)
        self.assertEqual(brain.light_left, 133 * 30)

    def test_dark_with_nothing_to_light_reads_word_of_recall(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        brain.recall, brain.torches, brain.food = 1, 0, 3
        view = town_view((5, 5), (5, 2), dlvl=1, stairs_type=0x9)
        self.assertIsNone(brain.recall_trip(command_obs(pos=(5, 5), dlvl=1, clvl=9), view))
        brain.dark = True
        decision = brain.recall_trip(command_obs(pos=(5, 5), dlvl=1, clvl=9), view)
        self.assertEqual((decision.layer, decision.reason), ("recall", "read Word of Recall"))
        brain.picking, brain.torches = None, 1
        self.assertIsNone(brain.recall_trip(command_obs(pos=(5, 5), dlvl=1, clvl=9), view))

    def test_an_outmatched_creature_in_contact_is_left_by_phase_door(self) -> None:
        # M5b round 53: four Human Priests fought DL5 Green Nagas from full HP.
        brain = Brain(GOALS["reach_dl8"])
        brain.food, brain.phase = 3, 2
        view = town_view((5, 5), (40, 40), dlvl=5)
        view.creatures[(5, 6)] = Creature("n", 5)
        brain.adjacent = [view.creatures[(5, 6)]]
        full = command_obs(pos=(5, 5), dlvl=5, clvl=8, hp=54, mhp=54)
        self.assertTrue(brain.outmatched(brain.adjacent[0], full))
        self.assertEqual(brain.phase_door(full, view).layer, "phase")

    def test_within_a_bite_of_death_drinks(self) -> None:
        # M5b round 52, seed 1008: 6 of 12 HP beside a Kobold (1d6), four
        # potions carried, and the next bite killed it.
        brain = Brain(GOALS["clvl10"])
        brain.food, brain.clw = 3, 4
        view = town_view((5, 5), (40, 40), dlvl=1, monsters={(5, 6)})
        view.creatures[(5, 6)] = Creature("k", 1)
        brain.adjacent = [view.creatures[(5, 6)]]
        hurt = command_obs(pos=(5, 5), dlvl=1, clvl=1, hp=6, mhp=12)
        self.assertTrue(brain.under_blow(hurt, view))
        self.assertEqual(brain.quaff(hurt, view).layer, "quaff")
        well = command_obs(pos=(5, 5), dlvl=1, clvl=1, hp=10, mhp=12)
        self.assertFalse(brain.under_blow(well, view))

    def test_a_caster_in_view_is_not_hunted_hurt(self) -> None:
        # M5b round 44, seed 1009: a level-4 Dwarf Priest went back for a
        # Novice Mage at 16 of 26 HP; one Cause Light Wounds (3d8) did 19.
        brain = Brain(GOALS["clvl10"])
        brain.food = 3
        view = town_view((5, 5), (40, 40), dlvl=2)
        view.creatures[(5, 9)] = Creature("p", 2)
        hurt = command_obs(pos=(5, 5), dlvl=2, clvl=4, hp=16, mhp=26)
        self.assertTrue(brain.under_spell(hurt, view))
        self.assertIsNone(brain.hunt(hurt, view))
        well = command_obs(pos=(5, 5), dlvl=2, clvl=4, hp=26, mhp=26)
        self.assertFalse(brain.under_spell(well, view))
        brain.clw = 1
        self.assertEqual(brain.quaff(hurt, view).layer, "quaff")

    def test_the_last_torch_is_the_light_home(self) -> None:
        # M5b round 45: five characters went dark far from town.
        brain = Brain(GOALS["reach_dl2"])
        brain.torches, brain.light_left = 1, 4000
        self.assertFalse(brain.light_low())
        brain.torches = 0
        self.assertTrue(brain.light_low())
        brain.lamp, brain.oil = True, 0
        self.assertFalse(brain.light_low())          # a lantern's own fuel is counted
        brain.light_left = 1000
        self.assertTrue(brain.light_low())

    def test_in_the_dark_with_no_way_up_take_the_down_stairs(self) -> None:
        # 2026-11-04: a level-11 Mage groped and searched DL1 for 140,000
        # steps beside a down staircase it knew, and starved.
        brain = Brain(GOALS["deep"])
        brain.dark, brain.torches, brain.lamp = True, 0, False
        view = town_view((5, 5), (9, 5), dlvl=1)                         # a down staircase, no up
        view.types[5 * COLS + 20] = UNKNOWN                              # an edge still to explore
        o = command_obs(pos=(5, 5), dlvl=1, clvl=11, hp=30, mhp=60)
        decision = brain.resupply(o, view)
        self.assertEqual((decision.layer, decision.reason), ("resupply", "light low: no way up, path to the down stairs"))
        from moria_playtest.brain import DARK_HOPS
        brain.dark_hops = DARK_HOPS                                      # hopped enough: grope for the way up
        self.assertNotEqual(getattr(brain.resupply(o, view), "reason", ""), "light low: no way up, path to the down stairs")
        brain.dark_hops = 0
        brain.dark = False                                               # lit: explore for the way up instead
        brain.torches = 1
        self.assertNotEqual(getattr(brain.resupply(o, view), "reason", ""), "light low: no way up, path to the down stairs")

    def test_starving_is_not_poison(self) -> None:
        # 2026-11-04: a starving Paladin prayed Slow Poison 5,189 times.
        brain = Brain(GOALS["deep"])
        for hp in (40, 39, 38, 37):
            brain.note_drain(command_obs(pos=(5, 5), dlvl=3, clvl=9, hp=hp, mhp=80, rows={23: "HP:40/80   Faint"}))
        self.assertFalse(brain.poisoned)

    def test_out_of_food_does_not_back_away_from_a_creature_long_gone(self) -> None:
        # 2026-11-04: a starving Paladin backed away from a creature seen long
        # before, undoing every step of its search for the stairs.
        brain = Brain(GOALS["deep"])
        brain.no_food = True
        brain.level.last_threat = (3, 5)
        view = town_view((5, 5), (30, 30), dlvl=3)
        hurt = command_obs(pos=(5, 5), dlvl=3, clvl=9, hp=30, mhp=80)
        self.assertIsNone(brain.rest(hurt, view))
        brain.level.near_until = hurt.step + 10                          # seen close just now: back away
        self.assertEqual(brain.rest(hurt, view).reason, "hurt: back away from where it was")

    def test_recharge_with_nothing_to_recharge_waits(self) -> None:
        # 2026-11-04: Mages cast Recharge Item I 114,410 times with no wand.
        from moria_playtest.brain import ON_ITEM_RETRY
        brain = Brain(GOALS["deep"])
        brain.magic.last = "Recharge Item I"
        o = command_obs(pos=(5, 5), dlvl=3, clvl=12, rows={0: "You have nothing there."})
        brain.decide(o, town_view((5, 5), (30, 30), dlvl=3))
        self.assertEqual(brain.on_item_after["Recharge Item I"], o.step + ON_ITEM_RETRY)

    def test_the_dim_warning_overrides_the_step_count(self) -> None:
        # 2026-11-04: rogues went dark while the count said light was left,
        # then searched dark dead ends until they starved.
        brain = Brain(GOALS["deep"])
        brain.torches, brain.light_left = 0, 4000
        brain.lamp = False
        brain.track_light("Your light is growing dim.")
        self.assertEqual(brain.light_left, 30)
        self.assertTrue(brain.light_low())

    def test_hp_lost_every_step_with_nothing_attacking_is_poison(self) -> None:
        # 2026-11-04: four characters walked or waited from 5 HP to death,
        # one with four Cure Light Wounds.
        brain = Brain(GOALS["deep"])
        view = town_view((5, 5), (30, 30), dlvl=5)
        for hp in (9, 8, 7):
            brain.attacked = False
            brain.note_drain(command_obs(pos=(5, 5), dlvl=5, clvl=10, hp=hp, mhp=80))
        self.assertFalse(brain.poisoned)                                # two losses so far
        brain.note_drain(command_obs(pos=(5, 5), dlvl=5, clvl=10, hp=6, mhp=80))
        self.assertTrue(brain.poisoned)
        brain.clw = 4
        self.assertEqual(brain.quaff(command_obs(pos=(5, 5), dlvl=5, clvl=10, hp=6, mhp=80), view).layer, "quaff")
        steady = Brain(GOALS["deep"])
        for hp in (9, 8, 8, 7, 7):                                       # a loss, then none: not a drain
            steady.note_drain(command_obs(pos=(5, 5), dlvl=5, clvl=10, hp=hp, mhp=80))
        self.assertFalse(steady.poisoned)

    def test_a_long_wear_message_keeps_the_picked_fuel(self) -> None:
        # M5b round 44, seed 1003: "(27 turns)" ran past 40 columns and was
        # dropped; the bot took the torch for a new one and its spares for
        # real ones.
        brain = Brain(GOALS["reach_dl2"])
        brain.torches, brain.picking, brain.listed = 3, "Wooden Torch", True
        o = command_obs(rows={0: "Wear which item? (a-c)", 2: " a) Wooden Torch (0 turns)",
                              3: " b) Wooden Torch (3 turns)", 4: " c) Wooden Torch (27 turns)"})
        self.assertEqual(brain.pick_item(o).key, ord("C"))
        brain.track_light("You are wearing a Wooden Torch.")
        self.assertEqual(brain.light_left, 27 * 30)
        self.assertEqual(brain.torches, 0)
        self.assertTrue(brain.light_low())


class UnstuckTest(unittest.TestCase):
    """M3 round 4 (§14.3): never sit on an exhausted level."""

    def corridor(self, dlvl, stairs, stairs_type=0x9, unknown_behind=False):
        view = town_view((5, 5), stairs, dlvl=dlvl, stairs_type=stairs_type)
        view.types = [WALL] * (COLS * ROWS)
        for x in range(3, 11):
            view.types[5 * COLS + x] = 0x0
        view.types[stairs[1] * COLS + stairs[0]] = stairs_type
        if unknown_behind:
            view.types[3 * COLS + 5] = UNKNOWN              # wall at (5,4), unknown behind it
        return view

    def test_stats_seen_last_count_on_a_store_screen(self) -> None:
        # M5b round 50, seed 1019: STR 10 assumed at the Weaponsmith bought a
        # Morningstar too heavy for the character.
        brain = Brain(GOALS["reach_dl2"])
        seen = command_obs(pos=(5, 5), dlvl=0, clvl=1, rows={22: "ST: 8  IN:11  WI:17  DX:13  CO:12  CH:16"})
        self.assertEqual(brain.stats(seen), (8, 13))
        self.assertEqual(brain.stats(command_obs(pos=(5, 5), dlvl=0, clvl=1)), (8, 13))
        self.assertLess(brain.melee_skill("Morningstar", seen), brain.melee_skill("Mace", seen))

    def test_hurt_by_a_town_creature_walks_to_the_stairs(self) -> None:
        # M5b round 48: a Battle-Scarred Veteran and a Mean-Looking Mercenary
        # killed Priests that fought them to the end.
        brain = Brain(GOALS["reach_dl2"])
        view = town_view((5, 5), (5, 2), dlvl=0, monsters={(6, 5)})
        hurt = command_obs(pos=(5, 5), dlvl=0, clvl=2, hp=5, mhp=16)
        self.assertEqual(brain.retreat(hurt, view).reason, "hurt by a town creature: walk to the stairs down")
        well = command_obs(pos=(5, 5), dlvl=0, clvl=2, hp=16, mhp=16)
        self.assertIsNone(brain.retreat(well, view))

    def test_the_general_store_is_skipped_when_it_has_nothing_to_sell(self) -> None:
        """2026-11-03: stair-scumming on DL1, weak characters climb to town every
        few dozen steps, and each trip walked to the General Store and out
        empty-handed. Skipped when nothing it sells is wanted, or when the last
        visit bought nothing with as much gold."""
        brain = Brain(GOALS["reach_dl2"])
        o = command_obs(pos=(5, 5), dlvl=0, clvl=2, rows={23: "HP:20/20  MP:0/0  AC:5  AU:40"})
        self.assertTrue(brain.general_worth_it(o))                    # five rations: wants more
        brain.general_gold = 40                                        # bought nothing with 40 gold
        self.assertFalse(brain.general_worth_it(o))
        richer = command_obs(pos=(5, 5), dlvl=0, clvl=2, rows={23: "HP:20/20  MP:0/0  AC:5  AU:90"})
        self.assertTrue(brain.general_worth_it(richer))
        brain.general_gold, brain.food, brain.oil = -1, 40, 20        # fed, lit and fuelled
        self.assertFalse(brain.general_worth_it(richer))

    def test_a_full_pack_in_town_drops_then_shops_again(self) -> None:
        # M5b round 47, seed 1014: the ration was refused for a full pack and
        # the visit ended; a level-9 Dwarf starved walking between shops.
        brain = Brain(GOALS["reach_dl2"])
        brain.shopped, brain.dropping, brain.listed = True, True, True
        o = command_obs(pos=(5, 5), dlvl=0, clvl=9,
                        rows={0: "Inventory", 2: " a) Ration of Food", 3: " b) Wooden Torch (0 turns)"})
        o.stage = "list"
        decision = brain.drop_prompt(o)
        self.assertEqual(decision.key, ord("B"))
        self.assertFalse(brain.shopped)

    def test_a_listing_corrects_the_counts(self) -> None:
        """2026-11-06: a level-27 Priest's count said no Word of Recall with
        two in the pack; it walked for supplies and stood in the dark 2.4
        million steps. The drop listing is the whole pack, the read list
        every scroll; a wear list says nothing of scrolls."""
        brain = Brain(GOALS["deep"])
        brain.recall, brain.phase, brain.clw = 0, 3, 5
        brain.dropping, brain.listed = True, True
        pack = command_obs(pos=(5, 5), dlvl=3, clvl=27, rows={
            0: "Inventory", 2: " a) 2 Scroll of Word of Recall", 3: " b) Potion of Cure Light Wounds",
            4: " c) Wooden Torch (0 turns)"})
        pack.stage = "list"
        brain.drop_prompt(pack)
        self.assertEqual((brain.recall, brain.phase, brain.clw), (2, 0, 1))
        brain.picking, brain.listed = "Wooden Torch", True
        wear = command_obs(rows={0: "Inventory", 2: " a) Wooden Torch (900 turns)"})
        wear.mode, wear.stage = Mode.ITEM, "list"
        brain.pick_item(wear)
        self.assertEqual(brain.recall, 2)                      # a wear list says nothing of scrolls
        brain.picking, brain.listed = "Scroll of Phase Door", True
        read = command_obs(rows={0: "Inventory", 2: " a) Scroll of Phase Door"})
        read.mode, read.stage = Mode.ITEM, "list"
        brain.pick_item(read)
        self.assertEqual((brain.recall, brain.phase), (0, 0))   # the read list holds every scroll; one read

    def test_stuck_with_no_recall_counted_looks_anyway(self) -> None:
        """2026-11-06: five Balrog characters searched sealed pockets to their
        budgets, four with Word of Recall their counts had lost."""
        from moria_playtest.brain import STUCK_STEPS
        brain = Brain(GOALS["deep"])
        brain.recall, brain.food = 0, 20
        view = town_view((5, 5), (40, 40), dlvl=3)
        o = command_obs(pos=(5, 5), dlvl=3, clvl=22, hp=200, mhp=200)
        self.assertIsNone(brain.recall_trip(o, view))                 # not stuck: no
        brain.level.since_progress = STUCK_STEPS
        self.assertEqual(brain.recall_trip(o, view).reason, "read Word of Recall")
        brain.picking = None
        self.assertIsNone(brain.recall_trip(o, view))                 # once a while, not every step

    def test_climb_back_hops_give_way_to_recall(self) -> None:
        """Arriving by up stairs is on a down staircase: hopping down and back
        up never got higher (2026-11-06: a level-27 Priest, DL3-DL4)."""
        from moria_playtest.brain import CLIMB_HOPS
        brain = Brain(GOALS["deep"])
        brain.recall, brain.food = 2, 20
        view = town_view((5, 5), (5, 5), dlvl=3)               # standing on a down staircase
        for _ in range(CLIMB_HOPS):
            self.assertEqual(brain.down_to_climb_back(view).key, ord(">"))
        self.assertIsNone(brain.down_to_climb_back(view))
        o = command_obs(pos=(5, 5), dlvl=3, clvl=27, hp=200, mhp=200)
        self.assertEqual(brain.recall_trip(o, view).reason, "read Word of Recall")
        brain.last_dlvl = 3
        brain.track(command_obs(pos=(5, 5), dlvl=2, clvl=27), view)   # higher than the hops began
        self.assertEqual(brain.climb_hops, 0)

    def test_stuck_after_hopping_with_no_recall_hops_again(self) -> None:
        """C128, 2026-11-06: hopped out with no Word of Recall, a level-12
        Warrior walked to a down staircase it would not take and searched
        dead ends, 27,000 steps on one DL3."""
        from moria_playtest.brain import CLIMB_HOPS, STUCK_STEPS
        brain = Brain(GOALS["deep"])
        brain.recall, brain.food = 0, 20
        view = town_view((5, 5), (5, 5), dlvl=3)               # standing on a down staircase
        for _ in range(CLIMB_HOPS):
            brain.down_to_climb_back(view)
        self.assertIsNone(brain.down_to_climb_back(view))      # explore for the way up first
        brain.level.since_progress = STUCK_STEPS
        self.assertEqual(brain.down_to_climb_back(view).key, ord(">"))

    def test_the_up_staircase_chosen_is_kept_past_a_creature_in_the_way(self) -> None:
        """C128, 2026-11-07: two up staircases far apart took turns whenever a
        creature stood in the cautious path, 66 squares west and 70 back east."""
        brain = Brain(GOALS["deep"])
        brain.food, brain.recall = 20, 0
        brain.torches, brain.lamp, brain.light_left = 0, False, 500     # light low: up for more
        walls = [(x, y) for x in range(0, 40) for y in (4, 6)]
        view = town_view((20, 5), (2, 5), walls=walls, dlvl=4, stairs_type=0xA)   # up stairs west
        view.types[5 * COLS + 38] = 0xA                           # and east
        brain.level.up_target = (2, 5)
        view.creatures = {(18, 5): Creature("w", 1)}               # a worm mass on the way west
        o = command_obs(pos=(20, 5), dlvl=4, clvl=20, hp=180, mhp=180, rows={23: "HP:180/180 MP:0/0 AC:5 AU:369"})
        decision = brain.resupply(o, view)
        self.assertEqual(brain.level.up_target, (2, 5))            # kept
        self.assertEqual(decision.key, DIRS[(-1, 0)])               # on west, at it

    def test_resupply_judges_what_is_left_to_explore_as_explore_does(self) -> None:
        """2026-11-06: an edge reachable only across a known trap: explore
        walked to it and resupply walked back to the down stairs, 300 entries
        of one DL3 square."""
        from moria_playtest.view import TYPE_TRAP
        brain = Brain(GOALS["deep"])
        walls = [(x, y) for x in range(0, 20) for y in (4, 6)]
        view = town_view((10, 5), (2, 5), walls=walls, dlvl=3)     # a down staircase west
        view.types[5 * COLS + 14] = TYPE_TRAP                      # a known trap east
        view.types[5 * COLS + 16] = UNKNOWN                        # unexplored past it
        for x in range(17, 40):
            view.types[5 * COLS + x] = UNKNOWN
        self.assertTrue(brain.explorable(view))                    # explore would cross it
        brain.level.dead_frontier |= view.frontier(traps=True)
        self.assertFalse(brain.explorable(view))

    def test_stuck_on_an_exhausted_level_hops_before_searching_walls(self) -> None:
        """2026-11-06: a level-21 Paladin with no way up searched the walls of
        one DL1 74,000 steps, a down staircase in view (C128 main queue)."""
        from moria_playtest.brain import STUCK_STEPS
        brain = Brain(GOALS["deep"])
        brain.recall, brain.food = 0, 20
        view = town_view((5, 5), (5, 5), walls=[(6, 5)], dlvl=1)   # on a down staircase, a wall beside it
        view.types[5 * COLS + 7] = UNKNOWN                         # and unknown space behind the wall
        o = command_obs(pos=(5, 5), dlvl=1, clvl=21, hp=155, mhp=155,
                        rows={23: "HP:155/155 MP:22/22 AC:27 AU:2627"})   # up for Word of Recall
        self.assertEqual(brain.stair_scum(o, view).layer, "search")
        brain.level.since_progress = STUCK_STEPS
        self.assertEqual(brain.stair_scum(o, view).key, ord(">"))

    def test_a_full_pack_refusing_recall_drops_in_town_and_tries_again(self) -> None:
        """2026-11-06: a level-19 Paladin's Word of Recall was refused for a
        full pack 170 times: with townspeople in view nothing was dropped in
        town, and the Alchemist stayed done for the visit."""
        from moria_playtest.brain import ALCHEMIST
        brain = Brain(GOALS["deep"])
        brain.at_store, brain.alchemist_done = ALCHEMIST, False
        refused = command_obs(pos=(5, 5), dlvl=0, clvl=19, rows={0: "Your pack is full."})
        refused.stage = "message"
        brain.store(refused)
        self.assertTrue(brain.pack_full and brain.alchemist_done)
        view = town_view((5, 5), (40, 40), dlvl=0)
        view.creatures = {(15, 5): Creature("t", 0)}             # a townsperson across the street
        o = command_obs(pos=(5, 5), dlvl=0, clvl=19)
        self.assertEqual(brain.drop_junk(o, view).layer, "drop")
        view.creatures = {(6, 5): Creature("t", 0)}              # one beside the player: not now
        self.assertIsNone(brain.drop_junk(o, view))
        brain.dropping, brain.listed = True, True
        pack = command_obs(pos=(5, 5), dlvl=0, clvl=19,
                           rows={0: "Inventory", 2: " a) Ration of Food", 3: " b) Wooden Torch (0 turns)"})
        pack.stage = "list"
        self.assertEqual(brain.drop_prompt(pack).key, ord("B"))
        self.assertFalse(brain.alchemist_done)                  # the Alchemist again, with room now

    def test_word_of_recall_trips_back_off_while_none_is_bought(self) -> None:
        """2026-11-06: one trip for it every 1,500 steps while none came; now
        1,500, then 3,000 at most (DL5 and below are shut without one, and
        rich level-26-28 characters wandered DL3-5 24,000 steps a wait), and
        back to 1,500 once one is carried."""
        from moria_playtest.brain import RECALL_WAIT_MAX, RESTOCK_WAIT
        brain = Brain(GOALS["deep"])
        view = town_view((5, 5), (40, 40), dlvl=0)

        def at(dlvl: int, step: int):
            o = command_obs(pos=(5, 5), dlvl=dlvl, clvl=19)
            o.step = step
            return o
        step, waits = 1000, []
        for _ in range(3):
            brain.track(at(0, step), view)
            step += 100
            brain.track(at(1, step), view)                     # left without one
            waits.append(brain.recall_trip_after - step)
        self.assertEqual(waits, [RESTOCK_WAIT, 2 * RESTOCK_WAIT, RECALL_WAIT_MAX])
        brain.recall = 1
        brain.track(at(0, step + 50), view)
        brain.track(at(1, step + 100), view)
        self.assertEqual(brain.recall_wait, RESTOCK_WAIT)

    def test_explore_ping_pong_drops_that_frontier(self) -> None:
        # M5b round 46, seed 1015: 5,000 steps between two corridor squares.
        brain = Brain(GOALS["reach_dl2"])
        brain.food = 3
        for k in range(8):
            pos = (5, 5) if k % 2 == 0 else (6, 5)
            view = self.corridor(2, (10, 5), unknown_behind=True)
            view.pos = pos
            brain.explore(command_obs(pos=pos, dlvl=2, clvl=3), view)
        self.assertTrue({(5, 5), (6, 5)} <= brain.level.dead_frontier)
        self.assertEqual(brain.level.explore_trail, [])

    def test_no_way_up_takes_the_down_stairs_even_when_not_ready(self) -> None:
        brain = Brain(GOALS["reach_dl2"].__class__("reach_dl5", "", lambda o: o.dlvl >= 5,
                                                   target_dlvl=5))
        brain.food = 3
        view = self.corridor(3, (9, 5))
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=3, clvl=3), view)
        # Too deep at level 3 (round 24), resupply takes it first (round 25).
        self.assertEqual(decision.key, DIRS[(1, 0)])
        self.assertIn(decision.layer, ("stair-scum", "resupply"))

    def test_too_deep_for_the_character_climbs(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        brain.food = 3
        view = town_view((5, 5), (5, 3), dlvl=4, stairs_type=0xA)
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=4, clvl=3), view)
        self.assertEqual((decision.layer, decision.key), ("resupply", DIRS[(0, -1)]))

    def test_nothing_left_to_do_searches_again_instead_of_resting(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        brain.food = 3
        view = self.corridor(2, (40, 40), unknown_behind=True)
        brain.track(command_obs(pos=(5, 5), dlvl=2, clvl=3), view)
        brain.level.searches = {spot: 6 for spot in view.search_spots(set())}
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=2, clvl=3), view)
        self.assertEqual(decision.layer, "search")


class LoopFixTest(unittest.TestCase):
    """M3 round 5: no endless re-search above goal depth; no town ping-pong."""

    def test_below_goal_depth_an_exhausted_level_with_a_way_out_is_left(self) -> None:
        brain = Brain(GOALS["reach_dl2"].__class__("reach_dl5", "", lambda o: o.dlvl >= 5,
                                                   target_dlvl=5))
        brain.food = 3
        view = UnstuckTest.corridor(UnstuckTest(), 3, (10, 5), stairs_type=0xA, unknown_behind=True)
        prepared(brain)
        brain.track(command_obs(pos=(5, 5), dlvl=3, clvl=5, hp=60, mhp=60), view)   # ready for DL3 (round 24)
        brain.level.searches = {spot: 6 for spot in view.search_spots(set())}
        brain.level.scum = True
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=3, clvl=5, hp=60, mhp=60), view)
        self.assertEqual((decision.layer, decision.key), ("stair-scum", DIRS[(1, 0)]))

    def test_an_empty_store_pauses_resupply_and_allows_going_deeper(self) -> None:
        brain = Brain(GOALS["reach_dl2"].__class__("reach_dl5", "", lambda o: o.dlvl >= 5, target_dlvl=5))
        brain.food = 0.5                                     # under the shallow reserve (M5b round 35)
        brain.hops = RESTOCK_HOPS                            # round 15: restock hops used up
        o = BrainM2Test.store_obs(BrainM2Test(), "menu", {3: " a) Iron Spike                 1 GP",
                                                          19: " B)uy  S)ell  Q)uit"})
        self.assertEqual(brain.decide(o, None).key, ord("Q"))
        view = town_view((5, 5), (5, 5), dlvl=1)            # on a down staircase
        view.types[5 * COLS + 20] = 0xA                      # up stairs known
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=1, clvl=3, hp=60, mhp=60), view)   # ready for DL2 (round 18)
        self.assertEqual((decision.layer, decision.key), ("descend", ord(">")))
        later = command_obs(pos=(5, 5), dlvl=1, clvl=3)
        later.step = o.step + 2000
        self.assertEqual(brain.decide(later, view).layer, "resupply")


class SealedTest(unittest.TestCase):
    """M3 round 7: sealed in, keep searching each spot well past the usual six."""

    def sealed_room(self):
        view = town_view((5, 5), (40, 40), dlvl=3)
        view.types = [WALL] * (COLS * ROWS)
        for x in range(4, 8):
            for y in range(4, 7):
                view.types[y * COLS + x] = 0x0
        view.types[2 * COLS + 5] = UNKNOWN                  # beyond the wall at (5, 3)
        return view

    def test_sealed_is_detected(self) -> None:
        self.assertTrue(Brain(GOALS["reach_dl2"]).sealed(self.sealed_room()))
        open_view = self.sealed_room()
        open_view.types[5 * COLS + 8] = 0xA                  # an up staircase by the room
        self.assertFalse(Brain(GOALS["reach_dl2"]).sealed(open_view))

    def test_no_frontier_under_a_creature(self) -> None:
        """M4 round 52: a Yellow Jelly on the only edge was walked into."""
        view = self.sealed_room()
        view.types[4 * COLS + 8] = UNKNOWN                   # edge squares (7, 4), (7, 5)
        self.assertIn((7, 4), view.frontier())
        view.creatures = {(7, 4): Creature("J", 3)}
        self.assertNotIn((7, 4), view.frontier())

    def test_sealed_in_and_short_of_food_reads_word_of_recall(self) -> None:
        """M4 round 53: sealed-in characters starved searching walls."""
        brain = Brain(GOALS["reach_dl2"])
        brain.food, brain.recall = 0.5, 1                    # under the shallow reserve (M5b round 35)
        view = self.sealed_room()
        brain.track(command_obs(pos=(5, 5), dlvl=2, clvl=5), view)
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=2, clvl=5, hp=40, mhp=40), view)
        self.assertEqual((decision.layer, decision.reason), ("recall", "read Word of Recall"))

    def test_no_recall_down_to_a_depth_too_deep_to_stay(self) -> None:
        """M8, 2026-11-02: a level-25 Balrog graduate climbed from DL28,
        recalled to town and recalled back to DL28, over and over."""
        from moria_playtest.goals import for_character
        decisions = {}
        for deepest in (22, 28):
            brain = Brain(for_character(GOALS["balrog"], "half-orc-warrior"))
            brain.food, brain.recall, brain.max_dlvl = 20, 3, deepest
            brain.lamp, brain.light_left, brain.oil = True, 9000, 5
            brain.shopped = brain.potions_done = brain.magic_done = brain.alchemist_done = True
            brain.market_done = brain.weapons_done = brain.armoury_done = True
            o = command_obs(pos=(5, 5), dlvl=0, clvl=25, hp=300, mhp=300)
            decisions[deepest] = brain.recall_trip(o, town_view((5, 5), (40, 40)))
        self.assertEqual(decisions[22].reason, "read Word of Recall")   # level 25 may stay on DL22
        self.assertIsNone(decisions[28])                                # not on DL28: the stairs instead

    def test_the_deep_goal_does_not_dive_past_its_level(self) -> None:
        """Maintainer, 2026-11-02: character level is the goal, not depth.
        Three levels over each depth, no taper: level 25 plays to DL22."""
        from moria_playtest.brain import ready_level
        goal = GOALS["deep"]
        self.assertIsNone(goal.ready_taper)
        self.assertEqual(max(d for d in range(1, 41) if ready_level(d, goal.ready_margin, goal.ready_taper) <= 25), 22)

    def test_a_felt_out_dead_end_is_no_way_out(self) -> None:
        """M4 round 52: seed 1005's only frontier was a dead end it had stood
        on; counting it as an exit kept the sealed-in searches from starting."""
        view = self.sealed_room()
        view.types[4 * COLS + 7] = 0x0
        view.types[4 * COLS + 8] = UNKNOWN                   # an edge at (7, 4)
        brain = Brain(GOALS["reach_dl2"])
        self.assertFalse(brain.sealed(view))
        brain.level.dead_frontier.update(view.frontier())   # (7, 4) and (7, 5)
        self.assertTrue(brain.sealed(view))

    def test_sealed_spots_include_walls_with_unreachable_floor_beyond(self) -> None:
        from moria_playtest.view import sealed_search_spots
        view = self.sealed_room()
        view.types[2 * COLS + 5] = 0x0                       # beyond (5, 3): known floor, not reachable
        self.assertEqual(view.search_spots(set()) & {(5, 4)}, set())
        self.assertIn((5, 4), sealed_search_spots(view, set()))

    def test_a_level_marked_for_leaving_is_still_explored_without_a_way_out(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        brain.food = 3
        view = self.sealed_room()
        view.types[5 * COLS + 8] = 0x0                       # an opening east...
        view.types[5 * COLS + 9] = UNKNOWN                   # ...into unexplored space
        brain.track(command_obs(pos=(5, 5), dlvl=1, clvl=3), view)
        brain.level.scum = True
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=1, clvl=3), view)
        self.assertEqual((decision.layer, decision.key), ("explore", DIRS[(1, 0)]))

    def test_sealed_in_keeps_searching_past_six(self) -> None:
        brain = Brain(GOALS["reach_dl2"].__class__("reach_dl5", "", lambda o: o.dlvl >= 5,
                                                   target_dlvl=5))
        brain.food = 3
        view = self.sealed_room()
        brain.track(command_obs(pos=(5, 5), dlvl=3, clvl=3), view)
        brain.level.searches = {spot: 6 for spot in view.search_spots(set())}
        brain.level.scum = True
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=3, clvl=3), view)
        self.assertEqual(decision.layer, "search")


class StationaryTest(unittest.TestCase):
    """M3 round 9: never fight creatures that never move; walk around them."""

    def test_stationary_glyphs_come_from_the_shipped_tier_data(self) -> None:
        from moria_playtest import knowledge
        self.assertIn("J", knowledge.stationary_glyphs())     # jellies (Yellow Jelly)
        self.assertNotIn("k", knowledge.stationary_glyphs())  # kobolds move

    def test_an_adjacent_jelly_is_not_attacked(self) -> None:
        brain = Brain(GOALS["reach_clvl2"])
        view = town_view((5, 5), (40, 40), dlvl=1)
        view.creatures = {(6, 5): Creature("J", 3)}
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=1, clvl=3), view)
        self.assertNotEqual(decision.layer, "fight")
        self.assertNotEqual(decision.layer, "hunt")

    def test_an_adjacent_mushroom_patch_is_swatted(self) -> None:
        """M4 round 36: a mushroom patch has 1 HP; walking past a ring of them
        paralysed seed 1020 at every step."""
        brain = Brain(GOALS["reach_dl2"])
        view = town_view((5, 5), (40, 40), dlvl=2)
        view.creatures = {(6, 6): Creature(",", 5)}
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=2, clvl=7, hp=30, mhp=80), view)
        self.assertEqual((decision.layer, decision.key), ("fight", DIRS[(1, 1)]))

    def test_a_jelly_is_still_never_fought(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        view = town_view((5, 5), (40, 40), dlvl=2)
        view.creatures = {(6, 6): Creature("J", 3)}
        self.assertNotEqual(brain.decide(command_obs(pos=(5, 5), dlvl=2, clvl=7), view).layer, "fight")

    def test_paths_keep_away_from_a_jelly(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        view = town_view((5, 5), (9, 5), dlvl=1)
        view.creatures = {(7, 5): Creature("J", 3)}
        brain.decide(command_obs(pos=(5, 5), dlvl=1, clvl=3), view)    # sets hazards
        step = view.step_toward({(9, 5)}, avoid_monsters=True)
        self.assertNotIn((5 + step[0], 5 + step[1]), {(6, 4), (6, 5), (6, 6)})


    def test_paths_keep_away_from_a_worm_mass(self) -> None:
        """M5 regression, seed 1006: 'w' is no slow glyph (the Giant Purple
        Worm is fast), so a White Worm mass walked away from was no hazard and
        the path to the stairs led straight back to it."""
        brain = Brain(GOALS["reach_dl2"])
        view = town_view((5, 5), (9, 5), dlvl=1)
        view.creatures = {(7, 5): Creature("w", 1)}
        brain.decide(command_obs(pos=(5, 5), dlvl=1, clvl=3), view)    # sets hazards
        self.assertIn((7, 5), view.hazards)
        step = view.step_toward({(9, 5)}, avoid_monsters=True)
        self.assertNotIn((5 + step[0], 5 + step[1]), {(6, 4), (6, 5), (6, 6)})
        view.creatures = {(7, 5): Creature("w", 29)}                     # a Giant Purple Worm
        brain.level.slow_seen.clear()
        brain.decide(command_obs(pos=(5, 5), dlvl=1, clvl=3), view)
        self.assertNotIn((7, 5), view.hazards)


    def test_a_worm_mass_out_of_sight_is_still_avoided(self) -> None:
        """2026-11-03: avoided only while in view, a White Worm mass by the
        nearer up staircase flipped the path between two staircases each
        time it showed, and a level-4 Warrior circled one DL1 level for
        18,000 steps until it starved. Out of sight it is still avoided,
        unless that leaves no way at all; beside its empty tile, forgotten."""
        walls = [(x, y) for x in range(0, 40) for y in (4, 6)]
        def corridor() -> View:
            view = town_view((10, 5), (2, 5), walls=walls, dlvl=1, stairs_type=0xA)
            view.types[5 * COLS + 30] = 0xA                       # a farther up staircase, east
            return view
        def at(pos: tuple[int, int], step: int):  # type: ignore[no-untyped-def]
            o = command_obs(pos=pos, dlvl=1, clvl=4)
            o.step = step
            return o
        brain = Brain(GOALS["reach_dl2"])
        view = corridor()
        view.creatures = {(6, 5): Creature("w", 1)}
        brain.decide(at((10, 5), 1000), view)
        self.assertEqual(view.step_toward(view.stairs_up(), avoid_monsters=True), (1, 0))   # east, away from it
        view = corridor()                         # 100 steps on, out of the light: past SLOW_MEMORY's hazard
        brain.last_move = None   # the fixture never moves the player: not a bump (round 17)
        brain.decide(at((10, 5), 1100), view)
        self.assertEqual(view.remembered, {(6, 5)})
        self.assertEqual(view.step_toward(view.stairs_up(), avoid_monsters=True), (1, 0))   # still east
        self.assertEqual(view.step_toward({(2, 5)}, avoid_monsters=True), (-1, 0))         # the only way: past it
        view = town_view((7, 5), (2, 5), walls=walls, dlvl=1, stairs_type=0xA)             # beside its tile, empty
        brain.last_move = None
        brain.decide(at((7, 5), 1101), view)
        self.assertEqual(view.remembered, set())

    def test_a_breeding_nest_out_of_sight_is_still_avoided(self) -> None:
        """C128, 2026-11-06: rats steered the path only while in view, and a
        level-19 Warrior walked east and back west along one DL1 corridor,
        79 times in 1,000 steps."""
        walls = [(x, y) for x in range(0, 40) for y in (4, 6)]
        def corridor() -> View:
            view = town_view((10, 5), (2, 5), walls=walls, dlvl=1, stairs_type=0xA)
            view.types[5 * COLS + 30] = 0xA                       # a farther up staircase, east
            return view
        def at(pos, step):  # type: ignore[no-untyped-def]
            o = command_obs(pos=pos, dlvl=1, clvl=19, hp=180, mhp=180)
            o.step = step
            return o
        brain = Brain(GOALS["reach_dl2"])
        view = corridor()
        view.creatures = {(6, 5): Creature("r", 1)}
        brain.decide(at((10, 5), 1000), view)
        view = corridor()                                     # out of sight
        brain.last_move = None
        brain.decide(at((10, 5), 1100), view)
        self.assertEqual(view.remembered, {(6, 5)})
        self.assertEqual(view.step_toward(view.stairs_up(), avoid_monsters=True), (1, 0))   # east, not past it
        view = corridor()
        brain.last_move = None
        from moria_playtest.brain import SLOW_AVOID
        brain.decide(at((10, 5), 1000 + SLOW_AVOID), view)
        self.assertEqual(view.remembered, set())              # long gone


class WornOutTest(unittest.TestCase):
    """2026-11-06: level-24+ deaths had AC 4 (priests, paladins) to 14
    (warriors) with 284,000 gold: acid had worn the armour to [14,-14] while
    the bot counted what it bought; a level-29 Priest played at CON 3."""

    EQUIPMENT = ["", " a) Weapon: Katana (+2,+2)", " b) Body:   Mithril Plate Mail", "            [14,-14]",
                 " c) Shield: Large Shield [3,-3]", " d) Head:   Steel Helm [2,-2]", " e) Hands:  Leather Gloves",
                 "            [1,-1]", " f) Feet:   Hard Leather Boots", "            [2,+2]",
                 " g) Light:  Wooden Torch (43 turns)", "    Ring:   (none)", "            Press any key"]

    def test_the_equipment_list_gives_the_armour_worn(self) -> None:
        self.assertEqual(Brain.read_equipment(self.EQUIPMENT),
                         {"ICAT_ARMOR": 0, "ICAT_SHIELD": 0, "ICAT_HELM": 0, "ICAT_GLOVES": 0, "ICAT_BOOTS": 4})
        self.assertIsNone(Brain.read_equipment(["You have no more Rations of Food.", ""]))

    def test_acid_damage_sends_it_to_read_the_list_and_then_to_town(self) -> None:
        from moria_playtest.brain import ARMOUR_HITS_TRIP
        brain = Brain(GOALS["deep"])
        brain.armour = {"ICAT_ARMOR": 16, "ICAT_SHIELD": 5, "ICAT_HELM": 4, "ICAT_GLOVES": 3, "ICAT_BOOTS": 4}
        view = town_view((5, 5), (40, 40), dlvl=20)
        o = command_obs(pos=(5, 5), dlvl=20, clvl=26, hp=200, mhp=200,
                        rows={0: "Your Mithril Plate Mail is damaged!", 23: "HP:200/200 MP:0/0 AC:4 AU:284000"})
        self.assertEqual(brain.decide(o, view).reason, "look at the armour worn")
        listing = command_obs(pos=(5, 5), dlvl=20, clvl=26)
        listing.rows = [r.ljust(40) for r in self.EQUIPMENT] + [" " * 40] * (25 - len(self.EQUIPMENT))   # '[' as shown
        listing.mode, listing.stage = Mode.DISMISS, "anykey"
        self.assertEqual(brain.decide(listing, None).reason, "armour worn: AC 4 by the list")
        self.assertEqual(brain.armour["ICAT_ARMOR"], 0)              # the Armoury now sees the gain
        brain.armour_hits, brain.gear_trip_after = ARMOUR_HITS_TRIP, 10**9
        self.assertTrue(brain.wants_gear(o))                         # worn out: go and replace it

    def test_a_drained_stat_buys_and_drinks_restoration(self) -> None:
        from moria_playtest.brain import ALCHEMIST, RESTORATION
        brain = Brain(GOALS["deep"])
        stats = "ST:16  IN:10  WI:17  DX:12  CO:{co}  CH:11"
        o = command_obs(pos=(5, 5), dlvl=20, clvl=10, rows={22: stats.format(co=15)})
        brain.track_stats(o)
        self.assertFalse(brain.restore_due)                          # first seen low: nothing drained yet
        brain.track_stats(command_obs(pos=(5, 5), dlvl=20, clvl=10, rows={22: stats.format(co=12)}))
        self.assertTrue(brain.restore_due)                           # CON 15 to 12: drained
        brain.at_store = ALCHEMIST
        self.assertIn(RESTORATION, brain.shopping_list(5000))
        brain.credit(RESTORATION, 1)
        view = town_view((5, 5), (40, 40), dlvl=20)
        self.assertEqual(brain.quaff(o, view).reason, "a stat drained: drink Restoration")
        old = Brain(GOALS["deep"])
        old.track_stats(command_obs(pos=(5, 5), dlvl=20, clvl=29, rows={22: stats.format(co=3)}))
        self.assertTrue(old.restore_due)                             # met high with no history: one, to be sure

    def test_rich_it_buys_gain_potions_for_unmaxed_stats_and_drinks_them(self) -> None:
        """2026-11-07: the potions of gain stat, bought at the Black Market
        for any stat short of 18/100 (maintainer: "MAX OUT ALL OF ITS
        STATS"), drunk when carried and nothing is close."""
        from moria_playtest.brain import BLACK_MARKET, GAIN_POTIONS, MARKET_GEAR_GOLD
        brain = Brain(GOALS["deep"])
        brain.track_stats(command_obs(pos=(5, 5), dlvl=20, clvl=30,
                                      rows={21: "ST:18/00  IN:10  WI:18/50",
                                            22: "DX:18/00  CO:17  CH:11"}))
        brain.at_store = BLACK_MARKET
        wants = brain.shopping_list(MARKET_GEAR_GOLD)
        gains = [w for w in wants if w in GAIN_POTIONS]
        self.assertEqual(gains[0], "Potion of Gain Constitution")   # the fighting stats first
        self.assertNotIn("Potion of Gain Strength", gains)          # 18/100, shown "18/00": maxed
        self.assertNotIn("Potion of Gain Dexterity", gains)
        self.assertIn("Potion of Gain Wisdom", gains)
        self.assertFalse([w for w in brain.shopping_list(MARKET_GEAR_GOLD - 1) if w in GAIN_POTIONS])  # not rich
        brain.credit("Potion of Gain Constitution", 1)
        view = town_view((5, 5), (40, 40), dlvl=0)
        o = command_obs(pos=(5, 5), dlvl=0, clvl=30)
        self.assertEqual(brain.quaff(o, view).reason, "drink Gain Constitution")
        brain.picking = "Potion of Gain Constitution"
        brain.forget_picking()
        self.assertIsNone(brain.quaff(o, view))                      # none carried after all

    def test_in_town_the_armour_is_read_with_townspeople_about(self) -> None:
        brain = Brain(GOALS["deep"])
        brain.equip_checked = False
        view = town_view((5, 5), (40, 40), dlvl=0)
        view.creatures = {(15, 5): Creature("t", 0)}             # a townsperson across the street
        o = command_obs(pos=(5, 5), dlvl=0, clvl=26)
        self.assertEqual(brain.check_equipment(o, view).reason, "look at the armour worn")

    def test_badly_hurt_with_no_potions_reads_word_of_recall(self) -> None:
        brain = Brain(GOALS["deep"])
        brain.recall, brain.clw, brain.food = 1, 0, 20
        view = town_view((5, 5), (40, 40), dlvl=22)
        o = command_obs(pos=(5, 5), dlvl=22, clvl=25, hp=40, mhp=200)
        self.assertEqual(brain.hurt_out(o, view).reason, "HP 40/200, no potions: read Word of Recall")
        brain.clw = 2
        self.assertIsNone(brain.hurt_out(o, view))                   # potions first (quaff)


    def test_with_no_escape_at_hand_it_recalls_out_sooner(self) -> None:
        """2026-11-07: level-32 Paladins, mana spent and no Phase Door,
        fought on to 7-11% of their HP while Word of Recall took its turns."""
        brain = Brain(GOALS["deep"])
        brain.recall, brain.clw, brain.food = 4, 0, 20
        view = town_view((5, 5), (40, 40), dlvl=29)
        o = command_obs(pos=(5, 5), dlvl=29, clvl=32, hp=110, mhp=245)
        self.assertEqual(brain.hurt_out(o, view).reason, "HP 110/245, no potions: read Word of Recall")
        brain.recalling, brain.phase = False, 3
        self.assertIsNone(brain.hurt_out(o, view))   # an escape held: 35% as before

    def test_potions_too_weak_for_the_danger_do_not_keep_it_fighting(self) -> None:
        """2026-11-07: a level-34 Priest carried 80 Cure Light Wounds, too
        weak for what was beside it, and fought on to its death."""
        brain = Brain(GOALS["deep"])
        brain.recall, brain.clw, brain.food = 4, 80, 20
        view = town_view((5, 5), (40, 40), dlvl=31)
        o = command_obs(pos=(5, 5), dlvl=31, clvl=34, hp=40, mhp=245)
        brain.danger = lambda pos, view, obs: 120   # type: ignore[method-assign]
        self.assertEqual(brain.hurt_out(o, view).reason, "HP 40/245, no potions: read Word of Recall")
        brain.recalling = False
        brain.danger = lambda pos, view, obs: 0     # type: ignore[method-assign]
        self.assertIsNone(brain.hurt_out(o, view))  # nothing to fear: rest

    def test_rich_it_keeps_teleportation_charges(self) -> None:
        """2026-11-07: a level-35 Priest with no staff read Phase Door four
        times at an Ancient Blue Dragon that kept finding it."""
        from moria_playtest.brain import MARKET_GEAR_GOLD, TELEPORT_CHARGES_RICH, TELEPORT_STAFF
        brain = Brain(GOALS["deep"])
        brain.wands[TELEPORT_STAFF] = 3
        self.assertNotIn(TELEPORT_STAFF, brain.wands_wanted())          # not rich: one with charges does
        brain.gold_seen = MARKET_GEAR_GOLD
        self.assertIn(TELEPORT_STAFF, brain.wands_wanted())
        brain.wands[TELEPORT_STAFF] = TELEPORT_CHARGES_RICH
        self.assertNotIn(TELEPORT_STAFF, brain.wands_wanted())

    def test_out_of_phase_door_a_scroll_of_teleportation_is_the_far_escape(self) -> None:
        """2026-11-08: a level-37 Priest, out of Phase Door and its staff
        spent, meleed an Earth Elemental to its death with 10,000K gold; the
        Alchemist sells Scrolls of Teleportation and it never carried one."""
        from moria_playtest.brain import ALCHEMIST, TELEPORT_RESERVE, TELEPORT_SCROLL, TELEPORT_STAFF
        brain = Brain(GOALS["deep"])
        o = command_obs(pos=(5, 5), dlvl=34, clvl=37, hp=140, mhp=291)
        self.assertIsNone(brain.far_escape(o, "why"))
        brain.teleports = 2
        decision = brain.far_escape(o, "why")
        self.assertEqual((decision.key, decision.reason, brain.picking), (ord("R"), f"why: read {TELEPORT_SCROLL}", TELEPORT_SCROLL))
        brain.wands[TELEPORT_STAFF] = 3
        self.assertEqual(brain.far_escape(o, "why").reason, f"why: use the {TELEPORT_STAFF}")   # the staff's charges first
        self.assertTrue(brain.can_phase(command_obs(pos=(5, 5), dlvl=34, clvl=37)))
        # Deep, it keeps a reserve and the Alchemist sells it
        brain.teleports, brain.max_dlvl = 0, 34
        self.assertEqual(brain.teleport_reserve(), TELEPORT_RESERVE)
        brain.at_store = ALCHEMIST
        self.assertIn(TELEPORT_SCROLL, brain.shopping_list(None))
        brain.max_dlvl = 5
        self.assertEqual(brain.teleport_reserve(), 0)

    def test_a_fast_breather_counts_both_breaths(self) -> None:
        """2026-11-08: a level-37 Priest at 186/296 HP fought an Ancient
        White Dragon (234 a breath, two moves a turn) and took 468 at once."""
        from moria_playtest import knowledge
        from moria_playtest.view import Creature
        brain = Brain(GOALS["deep"])
        fast = next(k for k, v in knowledge.moves().items() if v == 2.0 and knowledge.spell_burst().get(k))
        slow = next(k for k, v in knowledge.moves().items() if v == 1.0 and knowledge.spell_burst().get(k))
        burst = knowledge.spell_burst()
        o = command_obs(pos=(10, 10), dlvl=34)
        self.assertEqual(brain.turn_burst(Creature(glyph=fast[0], level=fast[1]), o), 2 * burst[fast])
        self.assertEqual(brain.turn_burst(Creature(glyph=slow[0], level=slow[1]), o), burst[slow])

    def test_a_deep_rich_character_stocks_for_the_depth(self) -> None:
        brain = Brain(GOALS["deep"])
        brain.clvl, brain.max_dlvl, brain.gold_seen = 34, 31, 4_000_000
        self.assertEqual((brain.strong_reserve(), brain.phase_reserve(), brain.recall_reserve()), (20, 20, 6))
        brain.max_dlvl, brain.gold_seen = 6, 3000
        self.assertEqual((brain.strong_reserve(), brain.phase_reserve(), brain.recall_reserve()), (10, 3, 2))

    def test_afraid_in_grave_danger_escapes_before_praying_remove_fear(self) -> None:
        """2026-11-07: a level-34 Priest prayed Remove Fear twice at 9/245 HP
        among four strong creatures and died."""
        from moria_playtest.goals import for_character
        from moria_playtest.magic import REMOVE_FEAR
        brain = Brain(for_character(GOALS["deep"], "half-troll-priest"))
        brain.afraid = True
        brain.magic.study_due, brain.magic.listed = False, True
        brain.magic.caster = lambda obs: True                      # type: ignore[method-assign]
        brain.magic.can = lambda obs, name: name == REMOVE_FEAR    # type: ignore[method-assign]
        view = town_view((5, 5), (40, 40), dlvl=31)
        o = command_obs(pos=(5, 5), dlvl=31, clvl=34, hp=9, mhp=245)
        brain.danger = lambda pos, view, obs: 60                   # type: ignore[method-assign]
        decision = brain.pray(o, view)
        self.assertTrue(decision is None or "Remove Fear" not in decision.reason)
        brain.danger = lambda pos, view, obs: 2                    # type: ignore[method-assign]
        self.assertEqual(brain.pray(o, view).reason, "afraid: pray Remove Fear")


class BreathGuardTest(unittest.TestCase):
    """2026-11-07: a level-32 Dwarf Priest healed to 89/166 and walked on in
    a Young Red Dragon's sight; its next breath (96) killed it."""

    def setUp(self) -> None:
        self.glyph, self.level = ("d", 29)
        self.burst = knowledge.spell_burst()[(self.glyph, self.level)]   # 88

    def view(self, walls=()):
        v = town_view((10, 10), (40, 40), dlvl=29, walls=walls)
        v.creatures = {(16, 10): Creature(self.glyph, self.level)}
        return v

    def test_in_a_lethal_breather_s_sight_it_teleports_first(self) -> None:
        from moria_playtest.brain import TELEPORT_STAFF
        brain = Brain(GOALS["deep"])
        brain.wands[TELEPORT_STAFF] = 3
        o = command_obs(pos=(10, 10), dlvl=29, clvl=32, hp=80, mhp=166)
        decision = brain.breath_guard(o, self.view())
        self.assertEqual((decision.layer, decision.reason), ("phase", f"the 'd' could breathe {self.burst}: use the {TELEPORT_STAFF}"))

    def test_with_no_escape_it_steps_out_of_sight(self) -> None:
        brain = Brain(GOALS["deep"])
        walls = [(11, 8), (11, 9), (11, 11), (11, 12)]   # a pillar column: (11, 9) and (11, 11) are wall
        o = command_obs(pos=(10, 10), dlvl=29, clvl=32, hp=80, mhp=166)
        view = self.view(walls=walls + [(12, 9), (12, 11)])
        decision = brain.breath_guard(o, view)
        self.assertEqual(decision.layer, "retreat")
        step = {v: k for k, v in DIRS.items()}[decision.key]
        hidden = (10 + step[0], 10 + step[1])
        self.assertFalse(Brain.sees(view, hidden, (16, 10)))

    def test_healthy_enough_it_does_not_hide(self) -> None:
        brain = Brain(GOALS["deep"])
        o = command_obs(pos=(10, 10), dlvl=29, clvl=32, hp=150, mhp=166)
        self.assertIsNone(brain.breath_guard(o, self.view()))

    def test_a_breath_from_out_of_sight_is_escaped_not_healed_through(self) -> None:
        """2026-11-07: a level-34 Half-Troll Priest took 232 of 245 from an
        Ancient Blue Dragon in the dark, prayed Cure Medium Wounds four times
        where it stood, and the second breath killed it."""
        from moria_playtest.brain import UNSEEN_BREATH_STEPS
        brain = Brain(GOALS["deep"])
        brain.phase, brain.last_hp = 2, 245
        view = town_view((10, 10), (40, 40), dlvl=31)                 # nothing in view
        o = command_obs(pos=(10, 10), dlvl=31, clvl=34, hp=13, mhp=245,
                        rows={0: "the Ancient Blue Dragon breathes fire!"})
        decision = brain.decide(o, view)
        self.assertEqual((decision.layer, decision.reason), ("phase", "breaths unseen could breathe 464: read Phase Door"))
        self.assertEqual(brain.level.deadly, (10, 10))                # one to leave: it could kill from full HP
        later = command_obs(pos=(10, 10), dlvl=31, clvl=34, hp=13, mhp=245)
        later.step = o.step + UNSEEN_BREATH_STEPS
        self.assertIsNone(brain.breath_guard(later, view))            # forgotten in time
        brain.level.breath = (o.step, 232)
        far = command_obs(pos=(35, 12), dlvl=31, clvl=34, hp=13, mhp=245)
        brain.decide(far, town_view((35, 12), (40, 40), dlvl=31))       # teleported 25 squares
        self.assertIsNone(brain.level.breath)

    def test_after_a_lethal_breath_it_escapes_before_a_small_heal(self) -> None:
        """2026-11-08: a level-37 Priest at 40/286, a Mature Multi-Hued Dragon's
        218 just taken, drank Cure Serious Wounds twice (the quaff layer came
        first) with its mana full for Portal; the next breath killed it."""
        from moria_playtest.brain import CSW
        brain = Brain(GOALS["deep"])
        brain.phase, brain.strong[CSW], brain.recall, brain.food, brain.clw = 2, 5, 3, 5, 20   # a deep Priest's stock
        view = town_view((10, 10), (40, 40), dlvl=34)                 # the breather out of sight
        brain.track(command_obs(pos=(10, 10), dlvl=34, clvl=37, hp=258, mhp=286), view)   # on the level already
        vampire = min(k for k in knowledge.strength() if k[0] == "V")   # in melee with it, as then
        view.creatures = {(11, 10): Creature(*vampire)}
        o = command_obs(pos=(10, 10), dlvl=34, clvl=37, hp=40, mhp=286, monsters=[(11, 10)])
        brain.level.breath = (o.step, 218)
        decision = brain.decide(o, view)
        self.assertEqual(decision.layer, "phase")
        self.assertIn("breaths unseen could breathe 436", decision.reason)

    def test_an_unseen_breath_counts_twice(self) -> None:
        """2026-11-08: a level-37 Priest took 106 from an unseen Young
        Multi-Hued Dragon, explored on at 179/285, and was at 74 after the
        next; with no sight line to leave, two more are as likely as one."""
        brain = Brain(GOALS["deep"])
        brain.phase = 2
        view = town_view((10, 10), (40, 40), dlvl=34)                 # nothing in view
        o = command_obs(pos=(10, 10), dlvl=34, clvl=37, hp=179, mhp=285)
        brain.level.breath = (o.step, 106)
        self.assertEqual(brain.breath_guard(o, view).reason, "breaths unseen could breathe 212: read Phase Door")
        well = command_obs(pos=(10, 10), dlvl=34, clvl=37, hp=250, mhp=285)
        self.assertIsNone(brain.breath_guard(well, view))             # 212 of 250: survivable


class ThreatDepthTest(unittest.TestCase):
    """Maintainer, 2026-11-08: "be like a real human player": a level-37
    Half-Troll Priest farmed DL34 for 235 experience a kill under the Balrog
    goal's three levels over each depth."""

    def priest(self, goal: str = "balrog") -> Brain:
        from moria_playtest.brain import CSW
        from moria_playtest.goals import for_character
        brain = Brain(for_character(GOALS[goal], "half-troll-priest"))
        brain.recall, brain.clw, brain.strong[CSW] = 3, 20, 5
        brain.wants_book_trip = lambda obs: False   # type: ignore[method-assign]   # its books bought
        return brain

    def deeper(self, brain: Brain, dlvl: int, clvl: int = 37, mhp: int = 290) -> bool:
        return brain.deeper_ok(command_obs(pos=(10, 10), dlvl=dlvl, clvl=clvl, hp=mhp, mhp=mhp))

    def test_as_deep_as_nothing_native_kills_in_a_turn(self) -> None:
        brain = self.priest()
        self.assertTrue(self.deeper(brain, 34))            # DL35: a Young Black Dragon's 128
        self.assertTrue(self.deeper(brain, 36))            # DL37: a Mature Red Dragon's 160
        self.assertFalse(self.deeper(brain, 37))           # no deeper than its own level
        self.assertFalse(self.deeper(brain, 37, clvl=38))  # DL38: an Ancient White Dragon's 468 of 290
        brain.jewel_names["Ring"] = "Ring of Resist Cold"
        self.assertTrue(self.deeper(brain, 37, clvl=38))   # 156 through the ring

    def test_resupply_and_recall_agree_with_it(self) -> None:
        """2026-11-09: resupply climbed from DL36 and town refused Word of
        Recall down to DL37 by the old margin: level-37 Priests walked down
        from DL1 and recalled up from DL16 for light, over and over."""
        brain = self.priest()
        o = command_obs(pos=(10, 10), dlvl=36, clvl=37, hp=290, mhp=290)
        self.assertTrue(brain.depth_ready(o, 36))
        self.assertTrue(brain.depth_ready(o, 37, slack=1))     # Word of Recall back down to DL37
        self.assertFalse(brain.depth_ready(o, 38, slack=1))    # an Ancient White Dragon's 468
        view = town_view((10, 10), (40, 40), dlvl=36)
        self.assertIsNone(brain.resupply(o, view))             # no climb from a depth it survives

    def test_town_recalls_to_one_level_past_ready_and_climbs(self) -> None:
        """2026-11-09: level-37 Priests whose deepest was DL38 walked down
        from DL1 every town trip; one level too deep is a climb."""
        decisions = {}
        for deepest in (38, 39):
            brain = self.priest()
            brain.food, brain.max_dlvl = 20, deepest
            brain.lamp, brain.light_left, brain.oil = True, 9000, 5
            brain.shopped = brain.potions_done = brain.magic_done = brain.alchemist_done = True
            brain.market_done = brain.weapons_done = brain.armoury_done = True
            o = command_obs(pos=(5, 5), dlvl=0, clvl=37, hp=290, mhp=290)
            decisions[deepest] = brain.recall_trip(o, town_view((5, 5), (40, 40)))
        self.assertEqual(decisions[38].reason, "read Word of Recall")   # then up a level
        self.assertIsNone(decisions[39])                                # two too deep: the stairs
        brain = self.priest()
        o = command_obs(pos=(10, 10), dlvl=38, clvl=37, hp=290, mhp=290)
        self.assertIsNotNone(brain.resupply(o, town_view((10, 10), (40, 40), dlvl=38)))   # climbs at DL38

    def test_only_from_level_30_and_only_for_the_balrog_goal(self) -> None:
        self.assertFalse(self.deeper(self.priest(), 27, clvl=29, mhp=230))   # the margin: DL26
        self.assertFalse(self.deeper(self.priest("deep"), 34))


class ScoutTest(unittest.TestCase):
    """2026-11-07: six of seven deaths of a level-34 Priest's copies were
    dragons, one breathing from a dark room never seen, at 224/245 HP."""

    def priest(self):
        from moria_playtest.goals import for_character
        from moria_playtest.magic import DETECT_EVIL
        brain = Brain(for_character(GOALS["deep"], "half-troll-priest"))
        brain.magic.caster = lambda obs: True                      # type: ignore[method-assign]
        brain.magic.can = lambda obs, name: name == DETECT_EVIL    # type: ignore[method-assign]
        return brain

    def test_a_deep_level_is_scouted_on_arrival_and_now_and_then(self) -> None:
        brain = self.priest()
        view = town_view((10, 10), (40, 40), dlvl=31)
        o = command_obs(pos=(10, 10), dlvl=31, clvl=34, hp=245, mhp=245)
        self.assertIn("Detect Evil", brain.scout(o, view).reason)
        self.assertIsNone(brain.scout(o, view))                     # not again at once

    def test_new_ground_on_the_screen_is_scouted_again(self) -> None:
        """2026-11-08: Detect Evil sees only the screen (VMS detect_evil), and
        "You sense no evil nearby." on arrival was followed by a Mature Red
        Dragon's 320 from the dark 68 steps on (C64 Balrog, clvl 37)."""
        from moria_playtest.brain import SCOUT_EVERY
        from moria_playtest.magic import DETECT_EVIL
        brain = self.priest()
        brain.magic.spare = lambda obs, name: name == DETECT_EVIL  # type: ignore[method-assign]
        view = town_view((30, 20), (40, 40), dlvl=31)
        o = command_obs(pos=(30, 20), dlvl=31, clvl=37, hp=285, mhp=285, view=(11, 10))
        self.assertIn("Detect Evil", brain.scout(o, view).reason)
        near = command_obs(pos=(39, 20), dlvl=31, clvl=37, hp=285, mhp=285, view=(20, 10))
        near.step = o.step + 9
        self.assertIsNone(brain.scout(near, view))                  # 9 of 38 columns: mostly seen
        far = command_obs(pos=(49, 20), dlvl=31, clvl=37, hp=285, mhp=285, view=(30, 10))
        far.step = o.step + 19
        self.assertIn("Detect Evil", brain.scout(far, view).reason) # half the screen new
        later = command_obs(pos=(49, 20), dlvl=31, clvl=37, hp=285, mhp=285, view=(30, 10))
        later.step = far.step + SCOUT_EVERY
        self.assertIn("Detect Evil", brain.scout(later, view).reason)   # and now and then
        brain.magic.spare = lambda obs, name: False                 # type: ignore[method-assign]
        again = command_obs(pos=(49, 20), dlvl=31, clvl=37, hp=285, mhp=285, view=(30, 10))
        again.step = later.step + SCOUT_EVERY
        self.assertIsNone(brain.scout(again, view))                 # not the mana for the heal

    def test_a_creature_that_kills_in_one_breath_sends_it_off_the_level(self) -> None:
        glyph, level = max(((k, v) for k, v in knowledge.spell_burst().items() if k[0] == "D"), key=lambda kv: kv[1])[0]
        brain = self.priest()
        view = town_view((10, 10), (14, 10), dlvl=31, stairs_type=0xA)   # up stairs 4 east
        view.creatures = {(30, 30): Creature(glyph, level)}             # detected, far off
        o = command_obs(pos=(10, 10), dlvl=31, clvl=34, hp=245, mhp=245)
        decision = brain.leave_deadly(o, view)
        self.assertEqual((decision.layer, decision.key), ("leave", DIRS[(1, 0)]))
        on = town_view((14, 10), (14, 10), dlvl=31, stairs_type=0xA)
        on.creatures = {}
        self.assertEqual(brain.leave_deadly(command_obs(pos=(14, 10), dlvl=31, clvl=34, hp=245, mhp=245), on).key,
                         ord("<"))                                       # remembered once seen


class ResistFireTest(unittest.TestCase):
    """2026-11-07: Moria8 breath is all fire (monster_cast_breath), and six
    of a level-34 Priest's first seven copies died to dragon breath with
    Resist Heat and Cold known."""

    def test_a_breather_in_view_is_resisted_first(self) -> None:
        from moria_playtest.goals import for_character
        from moria_playtest.magic import RESIST_HEAT_COLD
        brain = Brain(for_character(GOALS["deep"], "half-troll-priest"))
        brain.magic.caster = lambda obs: True                          # type: ignore[method-assign]
        brain.magic.can = lambda obs, name: name == RESIST_HEAT_COLD   # type: ignore[method-assign]
        view = town_view((10, 10), (40, 40), dlvl=31)
        infos = knowledge.breath_info()
        fire = max((k for k, (b, e, _) in infos.items() if e == {"fire"} and b < 245), key=lambda k: infos[k][0])
        view.creatures = {(16, 10): Creature(*fire)}
        o = command_obs(pos=(10, 10), dlvl=31, clvl=34, hp=245, mhp=245)
        self.assertIn(RESIST_HEAT_COLD, brain.resist_fire(o, view).reason)
        brain.magic.can = lambda obs, name: False                      # type: ignore[method-assign]
        brain.resist_heat = 2
        self.assertEqual(brain.resist_fire(o, view).reason,
                         f"a breath of {brain.turn_burst(Creature(*fire), o)} in view: drink Resist Heat")
        # Lightning, gas and acid are not resisted (monster_cast_breath): nothing to drink for them
        other = next(k for k, (b, e, _) in infos.items() if e == {"lightning"} and b >= 100)
        view.creatures = {(16, 10): Creature(*other)}
        self.assertIsNone(brain.resist_fire(o, view))

    def test_each_breather_is_resisted_by_its_own_element(self) -> None:
        """Review 2026-11-08: one lightning breather in view (or remembered)
        made the worst breath unresistable, and a fire breath that resisting
        cut to a third went unresisted; frost is resisted by the Resist Cold
        potion, and its ring is worth the Resist Fire ring."""
        from moria_playtest.brain import BLACK_MARKET, RESIST_COLD
        from moria_playtest.goals import for_character
        from moria_playtest.magic import RESIST_HEAT_COLD
        brain = Brain(for_character(GOALS["deep"], "half-troll-priest"))
        brain.magic.caster = lambda obs: True                          # type: ignore[method-assign]
        brain.magic.can = lambda obs, name: name == RESIST_HEAT_COLD   # type: ignore[method-assign]
        infos = knowledge.breath_info()
        fire = max((k for k, (b, e, _) in infos.items() if e == {"fire"} and b < 245), key=lambda k: infos[k][0])
        bolt = max((k for k, (b, e, _) in infos.items() if e == {"lightning"}), key=lambda k: infos[k][0])
        view = town_view((10, 10), (40, 40), dlvl=31)
        view.creatures = {(16, 10): Creature(*fire), (18, 10): Creature(*bolt)}
        o = command_obs(pos=(10, 10), dlvl=31, clvl=38, hp=400, mhp=400)   # the bolt survivable
        self.assertLess(brain.turn_burst(Creature(*bolt), o), 0.9 * o.hp)
        self.assertIn(RESIST_HEAT_COLD, brain.resist_fire(o, view).reason)
        # The same out of sight, both remembered on a deadly level
        brain.note_breathers(o, view)
        self.assertEqual(set(brain.level.breathers), {frozenset({"fire"}), frozenset({"lightning"}), frozenset()}
                         if infos[fire][2] or infos[bolt][2] else {frozenset({"fire"}), frozenset({"lightning"})})
        brain.level.deadly = (16, 10)
        self.assertIn(RESIST_HEAT_COLD, brain.resist_fire(o, town_view((10, 10), (40, 40), dlvl=31)).reason)
        # Frost: the Resist Cold potion, not Resist Heat
        brain.level = type(brain.level)()
        brain.magic.can = lambda obs, name: False                      # type: ignore[method-assign]
        frost = max((k for k, (b, e, _) in infos.items() if e == {"frost"} and b < 245), key=lambda k: infos[k][0])
        view.creatures = {(16, 10): Creature(*frost)}
        brain.resist_heat = 2
        self.assertIsNone(brain.resist_fire(o, view))
        brain.resist_cold = 2
        self.assertEqual(brain.resist_fire(o, view).reason,
                         f"a breath of {brain.turn_burst(Creature(*frost), o)} in view: drink Resist Cold")
        self.assertEqual(brain.picking, RESIST_COLD)
        # Bought rich at the Black Market from SCOUT_FROM deep, as Resist Heat
        brain.max_dlvl, brain.resist_cold, brain.at_store = 31, 0, BLACK_MARKET
        self.assertIn(RESIST_COLD, brain.shopping_list(100000))
        self.assertEqual(brain.jewel_value("Ring of Resist Cold"), brain.jewel_value("Ring of Resist Fire"))

    def test_a_fast_breather_lethal_in_two_resisted_breaths_is_escaped(self) -> None:
        """2026-11-08 review: at 100 HP the bot prayed Resist Heat and Cold
        at an Ancient White Dragon, one resisted breath 78, but it breathes
        twice a turn: 156."""
        from moria_playtest.brain import TELEPORT_STAFF
        from moria_playtest.goals import for_character
        from moria_playtest.magic import RESIST_HEAT_COLD
        infos, moves = knowledge.breath_info(), knowledge.moves()
        fast = max((k for k, (b, e, _) in infos.items() if "fire" in e and e <= {"fire", "frost"}
                    and moves.get(k, 1.0) == 2.0), key=lambda k: infos[k][0])
        one_resisted = infos[fast][0] // 3
        brain = Brain(for_character(GOALS["deep"], "half-troll-priest"))
        brain.magic.caster = lambda obs: True                          # type: ignore[method-assign]
        brain.magic.can = lambda obs, name: name == RESIST_HEAT_COLD   # type: ignore[method-assign]
        brain.wands[TELEPORT_STAFF] = 3
        view = town_view((10, 10), (40, 40), dlvl=31)
        view.creatures = {(16, 10): Creature(*fast)}
        hp = int(one_resisted / 0.9) + 2                               # one resisted breath is survivable, two are not
        o = command_obs(pos=(10, 10), dlvl=31, clvl=37, hp=hp, mhp=300)
        self.assertIsNone(brain.resist_fire(o, view))
        self.assertEqual(brain.breath_guard(o, view).layer, "phase")

    def test_a_breath_lethal_even_resisted_is_escaped_not_resisted(self) -> None:
        """2026-11-07: a level-34 Priest at 38/245 prayed Resist Heat and
        Cold in an Ancient White Dragon's sight; a third of its 234 still
        killed it."""
        from moria_playtest.goals import for_character
        from moria_playtest.magic import RESIST_HEAT_COLD
        brain = Brain(for_character(GOALS["deep"], "half-troll-priest"))
        brain.magic.caster = lambda obs: True                          # type: ignore[method-assign]
        brain.magic.can = lambda obs, name: name == RESIST_HEAT_COLD   # type: ignore[method-assign]
        brain.phase = 2
        kind = max(knowledge.spell_burst().items(), key=lambda kv: kv[1])[0]   # the biggest breath
        view = town_view((10, 10), (40, 40), dlvl=31)
        view.creatures = {(16, 10): Creature(*kind)}
        o = command_obs(pos=(10, 10), dlvl=31, clvl=34, hp=38, mhp=245)
        self.assertIsNone(brain.resist_fire(o, view))
        self.assertEqual(brain.breath_guard(o, view).layer, "phase")

    def test_a_breath_taken_resisted_counts_at_its_full_size(self) -> None:
        """2026-11-08: a level-36 Priest took 50 resisted from an unseen
        Mature Black Dragon, explored on at 121/264, and its next breath did
        153."""
        brain = Brain(GOALS["deep"])
        brain.resist_div = lambda obs, element, lasting=False, assume=frozenset(): (   # type: ignore[method-assign]
            3 if element in ("fire", "frost") and not lasting else 1)   # the potion's timer running, no ring
        o = command_obs(pos=(10, 10), dlvl=32, clvl=36, hp=109, mhp=264)
        brain.note_breath(o, town_view((10, 10), (40, 40), dlvl=32), 50, "fire")
        self.assertEqual(brain.level.breath[1], 150)
        self.assertEqual(brain.level.breather[1], 150)
        self.assertEqual(brain.level.breathers, {frozenset({"fire"}): (o.step, 150)})
        brain.level.breath = brain.level.breather = None
        brain.note_breath(o, town_view((10, 10), (40, 40), dlvl=32), 50, "acid")   # acid: nothing resists it
        self.assertEqual(brain.level.breath[1], 50)

    def test_a_second_breath_on_a_level_makes_it_one_to_leave(self) -> None:
        """2026-11-09: a level-37 Priest took four breaths of about 100 from a
        Young Multi-Hued Dragon on one level, healing and exploring between
        them, and died to the last."""
        brain = Brain(GOALS["deep"])
        view = town_view((10, 10), (40, 40), dlvl=37)
        o = command_obs(pos=(10, 10), dlvl=37, clvl=37, hp=184, mhp=285)
        brain.note_breath(o, view, 101, "gas")
        self.assertIsNone(brain.level.deadly)                          # one breath: not yet
        brain.note_breath(o, view, 82, "frost")
        self.assertEqual(brain.level.deadly, (10, 10))                 # the second: leave the level

    def test_with_a_lethal_breather_about_it_rests_before_exploring(self) -> None:
        """2026-11-07: a level-35 Priest phased from a Mature Black Dragon
        (160), explored on at 137-152/252 and died to its next breath."""
        from moria_playtest.brain import BREATHER_MEMORY, Decision
        brain = Brain(GOALS["deep"])
        kind = max(knowledge.spell_burst().items(), key=lambda kv: kv[1])[0]
        # A turn's worth: a fast breather breathes twice (review, 2026-11-08)
        worst = int(knowledge.spell_burst()[kind] * max(1.0, knowledge.moves().get(kind, 1.0)))
        seen = town_view((10, 10), (40, 40), dlvl=31)
        seen.creatures = {(16, 10): Creature(*kind)}
        brain.note_breathers(command_obs(pos=(10, 10), dlvl=31, clvl=35, hp=250, mhp=252), seen)
        gone = town_view((10, 10), (40, 40), dlvl=31)                 # out of sight now
        low = command_obs(pos=(10, 10), dlvl=31, clvl=35, hp=worst - 10, mhp=worst * 2)
        self.assertEqual(brain.rest(low, gone).reason, f"HP {worst - 10}/{worst * 2}: a breath of {worst} about, rest first")
        brain.clw = 5                                                   # potions: heal at once
        self.assertIn("drink Cure Light Wounds", brain.rest(low, gone).reason)
        full = command_obs(pos=(10, 10), dlvl=31, clvl=35, hp=worst - 10, mhp=worst - 10)
        self.assertNotIn("drink", (brain.rest(full, gone) or Decision(0, "", "")).reason)   # full: no potion
        brain.clw = 0
        later = command_obs(pos=(10, 10), dlvl=31, clvl=35, hp=worst - 10, mhp=worst * 2)
        later.step = low.step + BREATHER_MEMORY
        self.assertNotIn("about, rest first", (brain.rest(later, gone) or Decision(0, "", "")).reason)

    def test_on_a_deadly_level_far_from_the_stairs_it_reads_recall_first(self) -> None:
        """2026-11-08: a level-36 Priest walked 40 steps toward the stairs from
        an Ancient White Dragon (234 of 259) and was breathed on."""
        from moria_playtest.brain import LEAVE_WALK_STEPS
        brain = Brain(GOALS["deep"])
        brain.recall = 3
        brain.level.deadly = (30, 10)
        view = town_view((10, 10), (60, 40), dlvl=31)
        view.stairs_up = lambda: {(10 + LEAVE_WALK_STEPS + 5, 10)}          # type: ignore[method-assign]
        o = command_obs(pos=(10, 10), dlvl=31, clvl=36, hp=259, mhp=259)
        self.assertEqual(brain.leave_deadly(o, view).layer, "recall")
        brain.recalling = True
        self.assertIsNone(brain.leave_deadly(o, view))                      # recall coming: no long walk
        view.stairs_up = lambda: {(12, 10)}                                 # type: ignore[method-assign]
        self.assertEqual(brain.leave_deadly(o, view).layer, "leave")        # close: the stairs

    def test_on_a_deadly_level_it_keeps_resistance_up_out_of_sight(self) -> None:
        from moria_playtest.goals import for_character
        from moria_playtest.magic import RESIST_HEAT_COLD
        brain = Brain(for_character(GOALS["deep"], "half-troll-priest"))
        brain.magic.caster = lambda obs: True                          # type: ignore[method-assign]
        brain.magic.can = lambda obs, name: name == RESIST_HEAT_COLD   # type: ignore[method-assign]
        o = command_obs(pos=(10, 10), dlvl=31, clvl=36, hp=259, mhp=259)
        brain.level.deadly, brain.level.breather = (30, 10), (o.step, 234)
        brain.level.breathers = {frozenset({"fire"}): (o.step, 234)}
        view = town_view((10, 10), (40, 40), dlvl=31)                 # nothing in view
        self.assertIn(RESIST_HEAT_COLD, brain.resist_fire(o, view).reason)

    def test_hurt_it_resists_a_remembered_breath_that_could_kill_now(self) -> None:
        """2026-11-09: a level-37 Priest took 160 from an unseen Mature Red
        Dragon, cast Portal and prayed Cure Medium Wounds at 137/296; the next
        breath killed it."""
        from moria_playtest.goals import for_character
        from moria_playtest.magic import RESIST_HEAT_COLD
        brain = Brain(for_character(GOALS["deep"], "half-troll-priest"))
        brain.magic.caster = lambda obs: True                          # type: ignore[method-assign]
        brain.magic.can = lambda obs, name: name == RESIST_HEAT_COLD   # type: ignore[method-assign]
        view = town_view((10, 10), (40, 40), dlvl=37)                 # nothing in view
        hurt = command_obs(pos=(10, 10), dlvl=37, clvl=37, hp=137, mhp=296)
        brain.level.breather = (hurt.step, 160)
        brain.level.breathers = {frozenset({"fire"}): (hurt.step, 160)}
        self.assertIn(RESIST_HEAT_COLD, brain.resist_fire(hurt, view).reason)
        full = command_obs(pos=(10, 10), dlvl=37, clvl=37, hp=296, mhp=296)
        self.assertIsNone(brain.resist_fire(full, view))               # it cannot kill from full HP

    def test_a_resistance_timer_does_not_make_a_deadly_level_safe(self) -> None:
        """2026-11-07: a level-34 Priest resisted on sight of an Ancient White
        Dragon (234 as 78), so the level never read deadly; it explored on and
        died to the next breath at 230/245."""
        brain = Brain(GOALS["deep"])
        kind = max(knowledge.spell_burst().items(), key=lambda kv: kv[1])[0]
        worst = knowledge.spell_burst()[kind]
        brain.resist_div = lambda obs, element, lasting=False, assume=frozenset(): (   # type: ignore[method-assign]
            3 if element in ("fire", "frost") and not lasting else 1)   # the potion's timer running, no ring
        view = town_view((10, 10), (40, 40), dlvl=31)
        view.creatures = {(30, 10): Creature(*kind)}
        o = command_obs(pos=(10, 10), dlvl=31, clvl=34, hp=worst + 10, mhp=worst + 10)
        brain.leave_deadly(o, view)
        self.assertEqual(brain.level.deadly, (30, 10))

    def test_seeing_a_creature_that_could_kill_from_full_hp_marks_the_level_deadly(self) -> None:
        """2026-11-09: a level-37 Priest saw an Ancient White Dragon while
        other layers decided (resist, then leave-caster); the level never read
        deadly, and after a teleport it rested and explored until the next
        breath killed it."""
        brain = Brain(GOALS["deep"])
        kind = max(knowledge.spell_burst().items(), key=lambda kv: kv[1])[0]
        worst = int(knowledge.spell_burst()[kind] * max(1.0, knowledge.moves().get(kind, 1.0)))
        view = town_view((10, 10), (40, 40), dlvl=31)
        view.creatures = {(30, 10): Creature(*kind)}
        brain.note_breathers(command_obs(pos=(10, 10), dlvl=31, clvl=37, hp=worst + 10, mhp=worst + 10), view)
        self.assertEqual(brain.level.deadly, (30, 10))
        safe = Brain(GOALS["deep"])                                     # a breath it survives from full HP
        safe.note_breathers(command_obs(pos=(10, 10), dlvl=31, clvl=37, hp=worst * 2, mhp=worst * 2), view)
        self.assertIsNone(safe.level.deadly)

    def test_the_ring_of_resist_fire_cuts_a_fire_breath_to_a_third_and_no_other(self) -> None:
        """2026-11-08: breath is by element (VMS spells 20-24): the ring
        divides fire, not a lightning dragon's breath."""
        from moria_playtest.brain import TELEPORT_STAFF
        infos = knowledge.breath_info()
        fire = next(k for k, (b, e, _) in infos.items() if e == {"fire"} and b >= 30)
        lightning = next(k for k, (b, e, _) in infos.items() if e == {"lightning"} and b >= 30)
        for kind, resisted in ((fire, True), (lightning, False)):
            brain = Brain(GOALS["deep"])
            brain.wands[TELEPORT_STAFF] = 3
            view = town_view((10, 10), (40, 40), dlvl=29)
            view.creatures = {(16, 10): Creature(*kind)}
            hp = brain.turn_burst(Creature(*kind), command_obs(pos=(10, 10), dlvl=29))
            o = command_obs(pos=(10, 10), dlvl=29, clvl=32, hp=hp, mhp=2 * hp)
            self.assertIsNotNone(brain.breath_guard(o, view))          # one turn's breath against its HP
            brain.jewel_names["Ring"] = "Ring of Resist Fire"
            self.assertEqual(brain.resist_div(o, "fire"), 3)
            self.assertEqual(brain.resist_div(o, "lightning"), 1)
            self.assertEqual(brain.breath_guard(o, view) is None, resisted)
        self.assertGreater(brain.jewel_value("Ring of Resist Fire"), brain.jewel_value("Ring of Protection [+20]"))


class FoundJewelTest(unittest.TestCase):
    def test_a_better_ring_on_the_floor_is_picked_up_and_put_on(self) -> None:
        """2026-11-08: a level-36 Priest walked past a Ring of Resist Fire
        eight times on DL32 and died to fire breath."""
        brain = Brain(GOALS["deep"])
        brain.jewels = {"Ring": 30}                                    # Protection [+3]
        self.assertTrue(brain.jewel_better("Ring of Resist Fire"))
        self.assertFalse(brain.jewel_better("Ring of Protection [+2]"))
        o = command_obs(pos=(10, 10), dlvl=32, clvl=36, hp=260, mhp=260,
                        rows={0: "You picked up a Ring of Resist Fire."})
        decision = brain.decide(o, town_view((10, 10), (40, 40), dlvl=32))   # below, nothing close
        self.assertEqual(decision.reason, "wear the Ring of Resist Fire")
        self.assertEqual(brain.gear["Ring of Resist Fire"], ("jewel", ("Ring", 800)))


class LeaveCasterTest(unittest.TestCase):
    def test_far_from_the_stairs_it_heals_then_recalls_before_walking(self) -> None:
        """2026-11-08: a level-37 Priest walked 25 steps toward stairs at
        115-151/292 with an Ancient Blue Dragon (240) about."""
        from moria_playtest.brain import LEAVE_WALK_STEPS
        kind = max(knowledge.spell_burst().items(), key=lambda kv: kv[1])[0]
        brain = Brain(GOALS["deep"])
        o = command_obs(pos=(10, 10), dlvl=34, clvl=37, hp=115, mhp=292)
        brain.level.casters[kind] = o.step
        brain.strong["Potion of Cure Serious"] = 10
        brain.recall = 3
        view = town_view((10, 10), (60, 40), dlvl=34)
        view.stairs_up = lambda: {(10 + LEAVE_WALK_STEPS + 5, 10)}      # type: ignore[method-assign]
        self.assertIn("far from the stairs: drink Cure Serious Wounds", brain.leave_caster(o, view).reason)
        brain.strong["Potion of Cure Serious"] = 0
        self.assertEqual(brain.leave_caster(o, view).layer, "recall")

    def test_well_it_takes_the_stairs_rather_than_recall(self) -> None:
        """2026-11-09: at 285/285 a level-37 Priest read Word of Recall on DL35
        at casters Detect Evil had shown, over and over, town and back."""
        from moria_playtest.brain import LEAVE_WALK_STEPS
        kind = max(knowledge.spell_burst().items(), key=lambda kv: kv[1])[0]
        brain = Brain(GOALS["deep"])
        o = command_obs(pos=(10, 10), dlvl=35, clvl=37, hp=285, mhp=285)
        brain.level.casters[kind] = o.step
        brain.recall = 3
        view = town_view((10, 10), (60, 40), dlvl=35)
        view.stairs_up = lambda: {(10 + LEAVE_WALK_STEPS + 5, 10)}      # type: ignore[method-assign]
        decision = brain.leave_caster(o, view)
        self.assertEqual(decision.layer, "leave-caster")
        self.assertIn("path to the nearest staircase", decision.reason)


class DeepHealTest(unittest.TestCase):
    def test_deep_with_no_rest_to_be_had_it_heals_before_walking_on(self) -> None:
        """2026-11-08: a level-37 Priest phased from Black Oozes, explored on
        at 145/266 on DL34, and an Ancient White Dragon's breath killed it."""
        brain = Brain(GOALS["deep"])
        brain.strong["Potion of Cure Serious"] = 10
        view = town_view((10, 10), (40, 40), dlvl=34)
        o = command_obs(pos=(10, 10), dlvl=34, clvl=37, hp=145, mhp=266)
        brain.level.near_until = o.step + 50                           # something close lately: no rest
        self.assertIn("deep, no rest: drink Cure Serious Wounds", brain.rest(o, view).reason)
        o2 = command_obs(pos=(10, 10), dlvl=34, clvl=37, hp=145, mhp=266)
        brain.level.near_until = 0                                     # a rest to be had: rest
        self.assertEqual(brain.rest(o2, view).layer, "rest")


class FoundGainTest(unittest.TestCase):
    def test_a_gain_potion_on_the_floor_is_wanted_until_the_stat_is_maxed(self) -> None:
        """2026-11-08: a level-36 Priest walked past a Potion of Gain
        Constitution six times on DL32."""
        brain = Brain(GOALS["deep"])
        brain.track_stats(command_obs(pos=(5, 5), dlvl=32, clvl=36, rows={21: "ST:18/00  IN:10  WI:18/50",
                                                                          22: "DX:18/00  CO:17  CH:11"}))
        self.assertTrue(brain.gain_wanted("Potion of Gain Constitution"))
        self.assertFalse(brain.gain_wanted("Potion of Gain Strength"))           # 18/100
        self.assertFalse(brain.gain_wanted("Potion of Cure Light Wounds"))


class ParalyzerTest(unittest.TestCase):
    def test_beside_a_creature_that_paralysed_it_it_gets_out_of_reach_first(self) -> None:
        """2026-11-07: a level-35 Priest woke at 67/253 beside an Iridescent
        Beetle, drank a potion there, and was paralysed and killed."""
        brain = Brain(GOALS["deep"])
        name = next(n for n, g in knowledge.glyphs_of().items() if n == "Iridescent Beetle")
        glyph = sorted(knowledge.glyphs_of()[name])[0]
        view = town_view((10, 10), (40, 40), dlvl=31)
        view.creatures = {(11, 10): Creature(glyph, 30)}
        o = command_obs(pos=(10, 10), dlvl=31, clvl=35, hp=67, mhp=253)
        self.assertIsNone(brain.shake_paralyzer(o, view))             # not known to paralyse yet
        more = command_obs(pos=(10, 10), dlvl=31, clvl=35, hp=67, mhp=253,
                           rows={0: f"the {name} paralyzes you. -more-"})
        more.mode, more.stage = Mode.DISMISS, "more"
        brain.decide(more, None)                                      # learned behind -more-
        self.assertIn(name, brain.paralyzers)
        brain.phase = 3
        self.assertEqual(brain.shake_paralyzer(o, view).reason, f"beside the '{glyph}' that paralyses: read Phase Door")
        brain.phase = 0
        decision = brain.shake_paralyzer(o, view)
        self.assertEqual(decision.layer, "retreat")
        step = {v: k for k, v in DIRS.items()}[decision.key]
        from moria_playtest.brain import chebyshev
        self.assertGreater(chebyshev((10 + step[0], 10 + step[1]), (11, 10)), 1)
        brain.jewel_names["Amulet"] = "Amulet of the Magi"           # Free Action: no blow paralyses
        self.assertIsNone(brain.shake_paralyzer(o, view))

    def test_a_hold_person_caster_is_not_a_touch_paralyser(self) -> None:
        """Review 2026-11-08: Hold Person's "paralyzes you." comes from any
        range (monster_cast_hold); fleeing its glyph's neighbours did nothing."""
        self.assertIn("Iridescent Beetle", knowledge.touch_paralyzers())
        self.assertNotIn("Sorcerer", knowledge.touch_paralyzers())
        brain = Brain(GOALS["deep"])
        more = command_obs(pos=(10, 10), dlvl=31, clvl=35, hp=67, mhp=253,
                           rows={0: "the Sorcerer paralyzes you. -more-"})
        more.mode, more.stage = Mode.DISMISS, "more"
        brain.decide(more, None)
        self.assertEqual(brain.paralyzers, set())


class BlockerMassTest(unittest.TestCase):
    def test_the_mass_of_a_committed_blocker_is_fought_not_walked_away_from(self) -> None:
        """2026-11-07: the rest of a worm mass beside the blocker clear_way
        chose undid every step toward it, 100 times (C64, Apple II, a
        level-30 Balrog Warrior on DL2)."""
        glyph, level = sorted(k for k in knowledge.slow_kinds() if k[0] == "w")[0]
        brain = Brain(GOALS["deep"])
        view = town_view((5, 5), (40, 40), dlvl=2)
        view.creatures = {(6, 5): Creature(glyph, level), (6, 6): Creature(glyph, level)}
        o = command_obs(pos=(5, 5), dlvl=2, clvl=30, hp=300, mhp=300)
        brain.level.clear_target = (6, 5)
        self.assertEqual(brain.fight(o, view).layer, "fight")


class FleeTest(unittest.TestCase):
    """2026-11-03 traces: three runs for the stairs in four were broken off,
    most when the creature dropped out of sight and explore walked back
    toward it hurt. Once fled, fled: on to the stairs while short of hunting
    strength, the creature in view or not."""

    def test_a_retreat_under_way_goes_on_to_its_stairs(self) -> None:
        brain = prepared(Brain(GOALS["reach_dl2"]))
        brain.food = 5
        view = town_view((5, 5), (12, 5), dlvl=2, stairs_type=0xA)     # the up stairs east
        o = command_obs(pos=(5, 5), dlvl=2, clvl=4, hp=20, mhp=40)
        brain.level.retreat_to = (12, 5)
        decision = brain.retreat(o, view)                              # nothing in view any more
        self.assertEqual((decision.layer, decision.key), ("retreat", DIRS[(1, 0)]))
        well = command_obs(pos=(5, 5), dlvl=2, clvl=4, hp=36, mhp=40)  # back to hunting strength
        self.assertIsNone(brain.retreat(well, view))
        self.assertIsNone(brain.level.retreat_to)


class StepAwayTest(unittest.TestCase):
    """M4 round 1 (§15.3): never stand or search next to a creature that
    never moves (Yellow Jelly, White Mushroom patch)."""

    def test_a_path_past_a_jelly_is_walked_not_undone(self) -> None:
        """Round 32 stepped away from every adjacent stationary creature,
        then walked back: next to a Floating Eye on the way to the stairs it
        did so until paralysed to death. Passing it is one step."""
        brain = Brain(GOALS["reach_dl2"])
        view = town_view((5, 5), (8, 5), dlvl=1)
        view.types = [WALL] * (COLS * ROWS)
        for x in range(3, 10):
            view.types[5 * COLS + x] = 0x0                  # one-wide corridor to the stairs
        view.types[5 * COLS + 8] = 0x9
        view.creatures = {(6, 4): Creature("J", 3)}          # in the wall niche beside it
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=1, clvl=3), view)
        self.assertEqual(decision.key, DIRS[(1, 0)])

    def test_search_never_picks_a_spot_next_to_a_jelly(self) -> None:
        brain = Brain(GOALS["reach_dl2"].__class__("reach_dl5", "", lambda o: o.dlvl >= 5, target_dlvl=5))
        view = UnstuckTest.corridor(UnstuckTest(), 2, (40, 40), unknown_behind=True)
        brain.track(command_obs(pos=(5, 5), dlvl=2, clvl=3), view)
        spots = view.search_spots(set())
        self.assertIn((5, 5), spots)                          # the dead end is a search spot
        brain.level.stationary[(4, 4)] = Creature("J", 3)     # a jelly in the wall corner beside it
        decision = brain.search(command_obs(pos=(5, 5), dlvl=2, clvl=3), view, forced=True)
        self.assertFalse(decision is not None and decision.layer == "search" and decision.key == KEY_SEARCH)


class OutmatchedTest(unittest.TestCase):
    """M4 rounds 71-74: nagas (normal speed, 20% random moves, AC 40)
    killed 8-10 of ~20 reach_dl10 characters that died, fought to the end;
    a walking player outpaces them, so the level is left instead."""

    def test_nagas_are_outpaced_orcs_are_not(self) -> None:
        self.assertIn("n", knowledge.outpaced_glyphs())
        self.assertNotIn("o", knowledge.outpaced_glyphs())

    def test_a_strong_naga_close_sends_a_diver_to_the_stairs_at_full_hp(self) -> None:
        brain = Brain(GOALS["reach_dl8"])
        brain.food = 5
        view = town_view((5, 5), (2, 5), dlvl=6, stairs_type=0xA)
        view.creatures = {(7, 5): Creature("n", 5)}          # Green Naga: lore 40 HP, AC 40
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=6, clvl=6, hp=60, mhp=60), view)
        self.assertEqual((decision.layer, decision.key), ("retreat", DIRS[(-1, 0)]))
        self.assertTrue(brain.level.scum)                    # and the level is to be left

    def test_a_naga_the_character_has_outgrown_is_no_reason_to_leave(self) -> None:
        brain = Brain(GOALS["reach_dl8"])
        brain.food = 5
        view = town_view((5, 5), (2, 5), dlvl=6, stairs_type=0xA)
        view.creatures = {(7, 5): Creature("n", 5)}
        brain.weapon = ("Broad Sword", 0)   # and the strength to use it (M5a: fight_odds)
        o = command_obs(pos=(5, 5), dlvl=6, clvl=10, hp=90, mhp=90,
                        rows={19: "ST:18/50 DX:12", 23: "HP:90/90  MP:0/0   AC:20  AU:277"})
        decision = brain.decide(o, view)
        self.assertNotEqual(decision.layer, "retreat")
        self.assertFalse(brain.level.scum)


class MemoryTest(unittest.TestCase):
    """M4 round 33 (§15.5): what scrolls off the screen or strikes unseen is
    still there."""

    def test_an_unidentified_glyph_is_remembered_off_screen(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        view = town_view((5, 5), (40, 40), dlvl=2)
        view.screen, view.unknown = (0, 0, 40, 20), {(30, 18): "$"}
        brain.decide(command_obs(pos=(5, 5), dlvl=2, clvl=3), view)
        scrolled = town_view((5, 5), (40, 40), dlvl=2)
        scrolled.screen = (0, 0, 40, 18)                     # row 18 scrolled off
        brain.decide(command_obs(pos=(5, 5), dlvl=2, clvl=3), scrolled)
        self.assertEqual(scrolled.unknown.get((30, 18)), "$")
        back = town_view((5, 5), (40, 40), dlvl=2)
        back.screen = (0, 0, 40, 20)                         # on screen, and gone
        brain.decide(command_obs(pos=(5, 5), dlvl=2, clvl=3), back)
        self.assertNotIn((30, 18), back.unknown)
        self.assertEqual(brain.level.glyphs, {})

    def test_no_rest_for_a_while_after_an_unseen_attack(self) -> None:
        """Seed 1010: a Bloodshot Eye's gaze blinds; the bot rested beside it,
        was hit between rests, and starved there."""
        brain = Brain(GOALS["reach_dl2"])
        brain.food = 3
        view = town_view((5, 5), (40, 40), dlvl=2)
        hit = command_obs(pos=(5, 5), dlvl=2, clvl=5, hp=30, mhp=60, rows={0: "the Bloodshot Eye hits you."})
        brain.decide(hit, view)
        quiet = command_obs(pos=(5, 5), dlvl=2, clvl=5, hp=30, mhp=60)
        self.assertNotEqual(brain.decide(quiet, town_view((5, 5), (40, 40), dlvl=2)).layer, "rest")

    def test_no_rest_beside_an_unidentified_creature_glyph(self) -> None:
        """Seed 1016 (round 35): Creeping Copper Coins that follow are a new
        unidentified '$' each step; the bot rested beside them and was
        poisoned to death."""
        brain = Brain(GOALS["reach_dl2"])
        brain.food = 3
        view = town_view((5, 5), (40, 40), dlvl=2)
        view.unknown = {(4, 7): "$"}                       # knight's move: not in line to look at
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=2, clvl=5, hp=30, mhp=60), view)
        self.assertNotEqual(decision.layer, "rest")

    def test_walks_away_from_slow_creatures_with_no_stairs(self) -> None:
        """Seed 1008 (round 35) fought a nest of Creeping Copper Coins to 3 HP."""
        brain = Brain(GOALS["reach_dl2"])
        brain.food = 3
        view = town_view((5, 5), (40, 40), dlvl=2)          # down stairs only: no way up
        view.types[40 * COLS + 40] = 0x0
        view.creatures = {(6, 5): Creature("$", 4)}
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=2, clvl=5, hp=10, mhp=60), view)
        self.assertEqual((decision.layer, decision.reason), ("retreat", "walk away from a slower creature"))

    def test_a_slow_creature_in_the_way_is_fought_after_walking_back(self) -> None:
        """2026-11-03: a level-1 Ranger stepped between a White Worm mass and
        the path to the stairs 100 times; walked away from and straight back
        beside it, it is fought when the odds favour the character."""
        brain = Brain(GOALS["reach_dl2"])
        brain.food = 3
        def beside() -> View:
            view = town_view((5, 5), (40, 40), dlvl=1)
            view.creatures = {(6, 5): Creature("w", 1)}
            return view
        o = command_obs(pos=(5, 5), dlvl=1, clvl=3, hp=30, mhp=30)
        self.assertEqual(brain.decide(o, beside()).reason, "walk away from a slower creature")
        brain.trail = [(5, 5), (4, 5), (5, 5), (4, 5)]          # away and back, twice
        brain.last_move = None
        self.assertEqual(brain.decide(o, beside()).reason, "attack adjacent 'w'")
        coins = beside()
        coins.creatures = {(6, 5): Creature("$", 4)}             # Creeping Coins: still left
        brain.trail = [(5, 5), (4, 5), (5, 5), (4, 5)]
        brain.last_move = None
        self.assertEqual(brain.decide(o, coins).reason, "walk away from a slower creature")

    def test_backed_off_a_slow_creature_as_far_as_it_goes_it_rests(self) -> None:
        """2026-11-03 A/B: hurt with a slow creature seen lately, the bot
        stepped away from it, explore stepped back, and ten characters spent
        their whole 1,000,000-step budget so. In a dead end three squares from
        where the worm was, it rests (auto-rest stops if anything shows)."""
        from moria_playtest.brain import KEY_AUTOREST
        brain = Brain(GOALS["reach_dl2"])
        brain.food = 5
        walls = [(x, y) for x in range(0, 20) for y in (4, 6)] + [(1, 5)]
        def dead_end() -> View:
            return town_view((2, 5), (40, 40), walls=walls, dlvl=1)
        o = command_obs(pos=(2, 5), dlvl=1, clvl=3, hp=10, mhp=30)
        o.step = 1000
        brain.track(o, dead_end())                               # a new level: its memory starts here
        brain.level.slow_seen[(5, 5)] = 990
        brain.level.last_threat = (5, 5)
        decision = brain.rest(o, dead_end())
        self.assertEqual((decision.key, decision.reason), (KEY_AUTOREST, "HP 10/30: backed off a slow creature, rest"))
        brain.level.last_threat = (3, 5)                          # right beside: no rest there
        self.assertIsNone(brain.rest(o, dead_end()))

    def test_no_rest_just_after_a_creature_was_close(self) -> None:
        """Creeping Copper Coins follow one square behind, out of the light:
        resting a turn after each retreat step let them catch up (round 37)."""
        brain = Brain(GOALS["reach_dl2"])
        brain.food = 3
        view = town_view((5, 5), (40, 40), dlvl=2)
        view.creatures = {(7, 5): Creature("$", 4)}
        brain.decide(command_obs(pos=(5, 5), dlvl=2, clvl=5, hp=50, mhp=60), view)
        later = command_obs(pos=(4, 5), dlvl=2, clvl=5, hp=50, mhp=60)
        later.step = 2
        self.assertNotEqual(brain.decide(later, town_view((4, 5), (40, 40), dlvl=2)).layer, "rest")

    def test_short_of_food_hops_before_searching_walls(self) -> None:
        """Round 37: sealed in on DL1-2, seeds 1004 and 1016 searched walls
        until their food ran out; a hop to a fresh level beats searching."""
        brain = Brain(GOALS["reach_dl5"])
        brain.food = 0.5                                     # under the shallow reserve (M5b round 35)
        view = UnstuckTest.corridor(UnstuckTest(), 2, (9, 5), unknown_behind=True)   # down stairs only
        brain.track(command_obs(pos=(5, 5), dlvl=2, clvl=5), view)
        brain.level.searches = {spot: 1 for spot in view.search_spots(set())}   # searching under way
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=2, clvl=5), view)
        self.assertNotEqual(decision.layer, "search")
        self.assertIn(decision.layer, ("resupply", "stair-scum"))

    def test_no_rest_soon_after_seeing_slow_coins(self) -> None:
        """M4 round 61: coins caught up with a bot resting in the dark."""
        brain = prepared(Brain(GOALS["reach_dl2"]))
        brain.food = 3
        view = town_view((5, 5), (40, 40), dlvl=4)
        view.creatures = {(9, 5): Creature("$", 4)}
        brain.decide(command_obs(pos=(5, 5), dlvl=4, clvl=8, hp=40, mhp=60), view)
        view = town_view((5, 5), (40, 40), dlvl=4)
        o = command_obs(pos=(5, 5), dlvl=4, clvl=8, hp=40, mhp=60)
        o.step = 10
        self.assertNotEqual(brain.decide(o, view).layer, "rest")
        o.step = 40
        self.assertEqual(brain.decide(o, view).layer, "rest")

    def test_creeping_coins_are_left_when_hurt(self) -> None:
        """Round 45: each poison touch stacks; slow coins cannot follow."""
        brain = Brain(GOALS["reach_dl2"])
        brain.food = 3
        view = town_view((5, 5), (40, 40), dlvl=4)
        view.creatures = {(6, 5): Creature("$", 4)}
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=4, clvl=8, hp=40, mhp=60), view)
        self.assertEqual(decision.reason, "walk away from a slower creature")

    def test_creeping_coins_are_left_at_full_strength_too(self) -> None:
        """M4 round 58: coins fought at full strength still killed 6."""
        brain = Brain(GOALS["reach_dl2"])
        brain.food = 3
        view = town_view((5, 5), (40, 40), dlvl=4)
        view.creatures = {(6, 5): Creature("$", 4)}
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=4, clvl=8, hp=60, mhp=60), view)
        self.assertEqual(decision.reason, "walk away from a slower creature")

    def test_no_recall_and_the_gold_for_one_heads_for_town(self) -> None:
        """M5a round 2: a character that could not afford Word of Recall on
        its last visit played 35,000 steps on DL1-2 without one and starved
        in a sealed pocket."""
        brain = Brain(GOALS["clvl10"])
        brain.food, brain.recall = 10, 0
        o = command_obs(pos=(5, 5), dlvl=2, clvl=6, hp=60, mhp=60,
                        rows={23: "HP:60/60  MP:0/0   AC:20  AU:500"})
        self.assertTrue(brain.needs_resupply(o))
        brain.recall = 1
        self.assertFalse(brain.needs_resupply(o))
        brain.recall = 0
        poor = command_obs(pos=(5, 5), dlvl=2, clvl=6, hp=60, mhp=60,
                           rows={23: "HP:60/60  MP:0/0   AC:20  AU:300"})
        self.assertFalse(brain.needs_resupply(poor))
        brain.track(command_obs(pos=(5, 5), dlvl=0), town_view((5, 5), (40, 40)))   # a town visit
        o.step = 10
        self.assertFalse(brain.needs_resupply(o))        # not straight back: the Alchemist may have had none

    def test_the_last_scroll_is_kept_for_the_way_home(self) -> None:
        brain = Brain(GOALS["reach_dl8"])
        brain.food, brain.recall, brain.max_dlvl = 10, 1, 6
        brain.shopped = brain.potions_done = brain.alchemist_done = brain.market_done = True
        brain.weapons_done = brain.armoury_done = True
        o = command_obs(pos=(5, 5), dlvl=0, clvl=9, rows={23: "HP:60/60  MP:0/0   AC:20  AU:100"})
        self.assertIsNone(brain.recall_trip(o, town_view((5, 5), (40, 40))))
        brain.recall = 2
        self.assertEqual(brain.recall_trip(o, town_view((5, 5), (40, 40))).layer, "recall")

    def test_hurt_beside_slow_coins_steps_away_before_drinking(self) -> None:
        """M5a round 10: a Half-Elf drank five potions in a row beside a
        coin nest that hit harder than each potion healed."""
        brain = Brain(GOALS["reach_dl8"])
        brain.food, brain.clw = 5, 3
        view = town_view((5, 5), (40, 40), dlvl=4)
        view.creatures = {(6, 5): Creature("$", 4), (6, 6): Creature("$", 4)}
        o = command_obs(pos=(5, 5), dlvl=4, clvl=7, hp=14, mhp=72)
        decision = brain.decide(o, view)
        self.assertEqual(decision.layer, "retreat")
        self.assertIn(decision.key, (DIRS[(-1, 0)], DIRS[(-1, -1)], DIRS[(-1, 1)]))
        away = town_view((3, 5), (40, 40), dlvl=4)                     # out of reach: no potion (the potion rule:
        away.creatures = {(6, 5): Creature("$", 4)}                   # no danger, no drink)
        self.assertNotEqual(brain.decide(command_obs(pos=(3, 5), dlvl=4, clvl=7, hp=14, mhp=72), away).layer,
                         "quaff")

    def test_hungry_waits_to_eat_while_a_creature_closes_in(self) -> None:
        """M5a round 11: a Half-Elf stopped to eat with a Rattlesnake two
        squares behind it and died three turns later."""
        brain = Brain(GOALS["reach_dl8"])
        brain.food = 5
        hungry = {23: "HP:40/74  MP:0/0  AC:20  AU:277  Hungry"}   # 40 columns
        view = town_view((5, 5), (40, 40), dlvl=6)
        view.creatures = {(8, 5): Creature("R", 5)}
        o = command_obs(pos=(5, 5), dlvl=6, clvl=8, hp=40, mhp=74, rows=hungry)
        self.assertNotEqual(brain.decide(o, view).layer, "eat")
        weak = command_obs(pos=(5, 5), dlvl=6, clvl=8, hp=40, mhp=74,
                           rows={23: "HP:40/74  MP:0/0  AC:20  AU:277  Weak"})
        self.assertEqual(brain.eat(weak, view).layer, "eat")
        clear = town_view((5, 5), (40, 40), dlvl=6)
        self.assertEqual(brain.eat(o, clear).layer, "eat")

    def test_an_attack_never_labels_a_glyph_in_rock(self) -> None:
        """M5a focused round 12, seed 1018: Creeping Coins hit from the
        dark beside a treasure vein's '$'; the vein was taken for them and
        attacked (no game time) for 85,000 steps."""
        brain = Brain(GOALS["reach_dl8"])
        brain.food = 5
        view = town_view((5, 5), (40, 40), dlvl=5, walls=[(5, 6)])
        view.unknown = {(5, 6): "$", (6, 5): "$"}                      # a vein in the wall, the coins on floor
        o = command_obs(pos=(5, 5), dlvl=5, clvl=7, hp=60, mhp=72,
                        rows={0: "the Creeping Copper Coins hits you."})
        decision = brain.decide(o, view)
        self.assertNotEqual(brain.level.identified.get(((5, 6), "$"), ("", ""))[0], "creature")
        self.assertEqual(brain.level.identified.get(((6, 5), "$"), ("", ""))[0], "creature")
        self.assertNotEqual(decision.key, DIRS[(0, 1)])                 # never into the wall

    def test_out_of_food_fights_through_slow_coins(self) -> None:
        """M5a round 2: with no food, walking away from coins on the way to
        the stairs met them again each step; 7 characters starved there."""
        brain = Brain(GOALS["reach_dl2"])
        brain.food = 0
        view = town_view((5, 5), (40, 40), dlvl=4)
        view.creatures = {(6, 5): Creature("$", 4)}
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=4, clvl=8, hp=60, mhp=60), view)
        self.assertEqual((decision.layer, decision.key), ("fight", DIRS[(1, 0)]))

    def test_dropped_gold_is_collected(self) -> None:
        """MON-014: walk to identified gold in view, then pick it up."""
        brain = prepared(Brain(GOALS["reach_dl2"]))
        brain.food = 3
        view = town_view((5, 5), (40, 40), dlvl=4)
        view.screen = (0, 0, COLS, ROWS)
        view.unknown = {(8, 5): "$"}
        brain.track(command_obs(pos=(5, 5), dlvl=4, clvl=8), view)
        brain.level.identified[((8, 5), "$")] = ("item", "Copper")
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=4, clvl=8, hp=60, mhp=60), view)
        self.assertEqual((decision.layer, decision.key), ("collect", ord("L")))
        self.assertEqual(brain.collect_to, (8, 5))
        view = town_view((8, 5), (40, 40), dlvl=4)
        decision = brain.decide(command_obs(pos=(8, 5), dlvl=4, clvl=8, hp=60, mhp=60), view)
        self.assertEqual((decision.layer, decision.key), ("collect", ord("G")))
        self.assertIn((8, 5), brain.level.collected)

    def test_gold_is_collected_past_one_asleep_a_way_off(self) -> None:
        """C64 Balrog replay, 2026-11-06: a giant seen only from inside a room
        sent a level-23 Gnome in for its gold and out again."""
        from moria_playtest.brain import STILL_STEPS
        brain = prepared(Brain(GOALS["reach_dl2"]))
        brain.food = 3
        view = town_view((5, 5), (40, 40), dlvl=4)
        view.screen = (0, 0, COLS, ROWS)
        brain.items_seen[(8, 5)] = ("$", "Copper")              # gold seen
        view.creatures = {(12, 9): Creature("P", 20)}
        o = command_obs(pos=(5, 5), dlvl=4, clvl=23, hp=200, mhp=200)
        self.assertIsNone(brain.collect(o, view))              # just seen: it may be coming
        brain.level.still[(12, 9)] = ("P", 0)
        o.step = STILL_STEPS
        self.assertEqual(brain.collect(o, view).key, ord("L"))  # asleep: go on

    def test_identified_coins_stay_identified_when_they_move(self) -> None:
        """M4 round 46b: a looked-at Creeping Copper Coins read as an unknown
        '$' again after each step it took."""
        brain = Brain(GOALS["reach_dl2"])
        brain.food = 3
        view = town_view((5, 5), (40, 40), dlvl=4)
        view.screen = (0, 0, COLS, ROWS)
        view.unknown = {(8, 5): "$"}
        brain.track(command_obs(pos=(5, 5), dlvl=4, clvl=8), view)
        brain.level.identified[((8, 5), "$")] = ("creature", "Creeping Copper Coins")
        view = town_view((5, 5), (40, 40), dlvl=4)
        view.screen = (0, 0, COLS, ROWS)
        view.unknown = {(7, 5): "$"}
        brain.decide(command_obs(pos=(5, 5), dlvl=4, clvl=8, hp=40, mhp=60), view)
        self.assertIn((7, 5), view.creatures)
        self.assertEqual(view.creatures[(7, 5)].glyph, "$")

    def test_badly_hurt_backs_away_from_a_creature_out_of_sight(self) -> None:
        """M4 round 49: seed 1017 explored back into a Green Naga at 26/81."""
        brain = prepared(Brain(GOALS["reach_dl2"]))
        brain.food = 3
        view = town_view((5, 5), (40, 40), dlvl=4, monsters={(6, 5)})
        brain.decide(command_obs(pos=(5, 5), dlvl=4, clvl=8, hp=60, mhp=60), view)
        view = town_view((5, 5), (40, 40), dlvl=4)
        o = command_obs(pos=(5, 5), dlvl=4, clvl=8, hp=20, mhp=60)
        o.step = 1
        decision = brain.decide(o, view)
        self.assertEqual(decision.reason, "hurt: back away from where it was")
        self.assertEqual(decision.key, DIRS[(-1, -1)])

    def test_an_attack_behind_more_still_counts(self) -> None:
        """M4 round 51: paralysed, the White Mushroom patch's attacks showed
        only on -more- screens; the next command screen said "You can move
        again." and the bot rested beside it."""
        brain = Brain(GOALS["reach_dl2"])
        brain.food = 3
        view = town_view((5, 5), (40, 40), dlvl=4)
        view.unknown = {(6, 5): ","}
        brain.track(command_obs(pos=(5, 5), dlvl=4, clvl=8), view)
        more = command_obs(pos=(5, 5), rows={0: "the White Mushroom patch hits you -more-"})
        more.mode, more.stage = Mode.DISMISS, "more"
        brain.decide(more, None)
        o = command_obs(pos=(5, 5), dlvl=4, clvl=8, hp=30, mhp=60, rows={0: "You can move again."})
        o.step = 1
        decision = brain.decide(o, view)
        self.assertNotEqual(decision.layer, "rest")
        self.assertEqual(brain.level.identified.get(((6, 5), ","))[0], "creature")

    def test_no_standing_still_beside_a_mold(self) -> None:
        """M4 round 49: seed 1013 rested beside a Brown Mold until it died."""
        brain = Brain(GOALS["reach_dl2"])
        brain.food = 3
        view = town_view((5, 5), (40, 40), dlvl=4, monsters=frozenset())
        view.creatures = {(6, 5): Creature("m", 3)}
        brain.track(command_obs(pos=(5, 5), dlvl=4, clvl=8), view)
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=4, clvl=8, hp=40, mhp=60), view)
        self.assertIn(decision.key, DIRS.values())
        step = next(d for d, k in DIRS.items() if k == decision.key)
        self.assertGreater(max(abs(5 + step[0] - 6), abs(5 + step[1] - 5)), 1)

    def test_gold_beside_a_stationary_creature_is_left(self) -> None:
        """M4 round 46: gold beside a Floating Eye or Yellow Jelly drew the
        bot back to it again and again."""
        brain = Brain(GOALS["reach_dl2"])
        brain.food = 3
        view = town_view((5, 5), (40, 40), dlvl=4)
        view.screen = (0, 0, COLS, ROWS)
        view.unknown = {(8, 5): "$"}
        brain.track(command_obs(pos=(5, 5), dlvl=4, clvl=8), view)
        brain.level.identified[((8, 5), "$")] = ("item", "Copper")
        brain.level.stationary[(9, 5)] = Creature("j", 3)
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=4, clvl=8, hp=60, mhp=60), view)
        self.assertNotEqual(decision.layer, "collect")

    def test_no_rest_when_starving(self) -> None:
        """Seed 1008: out of food with no way up known yet, resupply has no
        path, and resting (no healing, 1 HP a turn) starved the character."""
        brain = Brain(GOALS["reach_dl2"])
        brain.food, brain.no_food = 0, True
        view = UnstuckTest.corridor(UnstuckTest(), 2, (40, 40), unknown_behind=True)
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=2, clvl=5, hp=30, mhp=60), view)
        self.assertNotEqual(decision.layer, "rest")


class SealedHazardTest(unittest.TestCase):
    """M4 round 91: seed 1006 searched 21,700 turns; a remembered stationary
    creature beside the only door kept the square in front of it unsearched."""

    def test_sealed_in_a_weak_remembered_stationary_creature_is_hunted(self) -> None:
        brain = Brain(GOALS["clvl10"])
        brain.food = 5
        view = SealedTest.sealed_room(SealedTest())
        o = command_obs(pos=(5, 5), dlvl=3, clvl=6, hp=60, mhp=60)
        brain.track(o, view)
        brain.level.stationary[(7, 6)] = Creature(",", 1)    # a mushroom patch, out of sight
        decision = brain.decide(o, view)
        self.assertEqual(decision.layer, "fight")
        self.assertIn("sealed in", decision.reason)


    def test_an_approach_that_went_nowhere_is_blocked_and_rechosen(self) -> None:
        brain = Brain(GOALS["clvl10"])
        brain.food = 5
        o = command_obs(pos=(5, 5), dlvl=3, clvl=6, hp=60, mhp=60)
        brain.track(o, SealedTest.sealed_room(SealedTest()))
        brain.level.stationary[(7, 6)] = Creature(",", 1)
        first = brain.decide(o, SealedTest.sealed_room(SealedTest()))
        self.assertIn("sealed in: approach", first.reason)
        step = next(d for d, k in DIRS.items() if k == first.key)
        again = brain.decide(o, SealedTest.sealed_room(SealedTest()))   # still on (5, 5)
        self.assertIn((5 + step[0], 5 + step[1]), brain.level.bumped)
        self.assertNotEqual(again.key, first.key)

class StuckDoorTest(unittest.TestCase):
    """M4 round 83: seed 1006 gave up on its room's only (stuck) door and
    searched the walls for 22,000 turns."""

    def test_a_door_given_up_on_is_bashed_again_when_sealed_in(self) -> None:
        brain = Brain(GOALS["clvl10"])
        brain.food = 5
        view = town_view((5, 5), (40, 40), dlvl=2)
        view.types = [WALL] * (COLS * ROWS)
        for x in range(3, 8):
            view.types[5 * COLS + x] = 0x0                  # a corridor stub
        view.types[5 * COLS + 8] = 0x8                      # its closed door, east
        view.types[5 * COLS + 9] = UNKNOWN                  # unexplored beyond
        brain.track(command_obs(pos=(7, 5), dlvl=2, clvl=3), view)
        brain.level.blocked.add((8, 5))
        brain.level.door_attempts[(8, 5)] = 11
        view.pos = (7, 5)
        decision = brain.decide(command_obs(pos=(7, 5), dlvl=2, clvl=3), view)
        self.assertIn(decision.key, (ord("O"), KEY_BASH))
        self.assertNotIn((8, 5), brain.level.blocked)


class UnseenCasterTest(unittest.TestCase):
    """M4 round 89: seed 1028 auto-rested under a hidden Novice Priest's
    spells because a Floating Eye was in view."""

    def test_no_rest_when_the_attacker_is_not_what_is_in_view(self) -> None:
        brain = Brain(GOALS["clvl10"])
        brain.food = 5
        view = town_view((5, 5), (40, 40), dlvl=3)
        view.creatures = {(12, 9): Creature("e", 1)}
        o = command_obs(pos=(5, 5), dlvl=3, clvl=6, hp=30, mhp=71, rows={0: "the Novice Priest casts a spell."})
        decision = brain.decide(o, view)
        self.assertTrue(brain.unseen_attack)
        self.assertNotEqual(decision.layer, "rest")


class UnseenSearchTest(unittest.TestCase):
    """M4 round 90: seed 1013 searched a dead end under an unseen Novice
    Priest's spells until dead."""

    def test_no_searching_in_place_after_an_unseen_attack(self) -> None:
        brain = Brain(GOALS["clvl10"])
        brain.food = 5
        view = UnstuckTest.corridor(UnstuckTest(), 2, (40, 40), unknown_behind=True)
        o = command_obs(pos=(5, 5), dlvl=2, clvl=4, hp=40, mhp=51)
        brain.track(o, view)
        brain.level.unseen_until = o.step + 10
        decision = brain.decide(o, view)
        self.assertNotEqual(decision.key, KEY_SEARCH)


class CrowdTest(unittest.TestCase):
    """M4 round 88: seed 1017 walked off its arrival stairs into a Creeping
    Coins nest."""

    def test_a_crowd_by_the_stairs_takes_them_either_way(self) -> None:
        for stairs, key in ((0xA, ord("<")), (0x9, ord(">"))):
            brain = Brain(GOALS["clvl10"])
            brain.food = 5
            view = town_view((5, 5), (5, 5), dlvl=5, stairs_type=stairs)
            view.creatures = {(7, 5): Creature("$", 4), (6, 7): Creature("$", 4)}
            decision = brain.decide(command_obs(pos=(5, 5), dlvl=5, clvl=8, hp=90, mhp=90), view)
            self.assertEqual((decision.layer, decision.key), ("retreat", key))

    def test_one_creature_is_no_crowd(self) -> None:
        brain = Brain(GOALS["clvl10"])
        brain.food = 5
        view = town_view((5, 5), (5, 5), dlvl=5, stairs_type=0xA)
        view.creatures = {(7, 5): Creature("$", 4)}
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=5, clvl=8, hp=90, mhp=90), view)
        self.assertNotEqual(decision.reason, "1 creatures close: take the stairs")
        self.assertNotIn("creatures close", decision.reason)


class MushroomTest(unittest.TestCase):
    """M4 round 86: seed 1005 looked at a White Mushroom patch through an
    identified item, filed it as "a Rock", and stood beside it until dead."""

    def test_no_look_through_an_identified_item(self) -> None:
        brain = Brain(GOALS["reach_dl8"])
        brain.food = 5
        view = town_view((8, 5), (40, 40), dlvl=3)
        view.unknown = {(6, 5): "[", (4, 5): ","}
        brain.track(command_obs(pos=(8, 5), dlvl=3, clvl=6), view)
        brain.level.identified[((6, 5), "[")] = ("item", "Rock")
        brain.items_seen = {(6, 5): ("[", "Rock")}
        del view.unknown[(6, 5)]
        self.assertIsNone(brain.look(command_obs(pos=(8, 5), dlvl=3, clvl=6), view))

    def test_an_attack_relabels_an_item_as_the_attacker(self) -> None:
        brain = Brain(GOALS["reach_dl8"])
        brain.food = 5
        view = town_view((5, 5), (40, 40), dlvl=3)
        view.unknown = {(4, 5): ","}
        brain.track(command_obs(pos=(5, 5), dlvl=3, clvl=6), view)
        brain.level.identified[((4, 5), ",")] = ("item", "Rock")
        brain.level.looked.add(((5, 5), (4, 5)))
        hit = command_obs(pos=(5, 5), dlvl=3, clvl=6, hp=60, mhp=90,
                          rows={0: "the White Mushroom patch hits you."})
        decision = brain.decide(hit, view)
        self.assertEqual(brain.level.identified[((4, 5), ",")][0], "creature")
        self.assertEqual((decision.layer, decision.key), ("fight", DIRS[(-1, 0)]))   # swatted


class TileMemoryTest(unittest.TestCase):
    """M4 round 70: the game forgets dark floor once the light moves on; a
    player does not (seed 1023 oscillated 6,000 steps)."""

    def test_forgotten_floor_stays_known(self) -> None:
        brain = Brain(GOALS["reach_dl5"])
        brain.food = 3
        view = town_view((5, 5), (40, 40), dlvl=2)
        brain.decide(command_obs(pos=(5, 5), dlvl=2, clvl=3), view)
        later = town_view((5, 5), (40, 40), dlvl=2)
        later.types[6 * COLS + 6] = UNKNOWN                  # forgotten after the torch moved on
        brain.decide(command_obs(pos=(5, 5), dlvl=2, clvl=3), later)
        self.assertEqual(later.type_at(6, 6), 0x0)

    def test_a_new_level_starts_with_nothing_remembered(self) -> None:
        brain = Brain(GOALS["reach_dl5"])
        brain.food = 3
        brain.decide(command_obs(pos=(5, 5), dlvl=2, clvl=3), town_view((5, 5), (40, 40), dlvl=2))
        later = town_view((5, 5), (40, 40), dlvl=3)
        later.types[6 * COLS + 6] = UNKNOWN
        brain.decide(command_obs(pos=(5, 5), dlvl=3, clvl=3), later)
        self.assertEqual(later.type_at(6, 6), UNKNOWN)


class OscillationTest(unittest.TestCase):
    """M4 round 34 (§15.5): back and forth between two squares is no
    progress, whichever layer or view change flips the choice."""

    def test_a_sixth_flip_is_blocked_and_rechosen(self) -> None:
        from moria_playtest.brain import Decision
        brain = Brain(GOALS["reach_dl2"])
        view = town_view((6, 5), (40, 40), dlvl=2)
        brain.track(command_obs(pos=(6, 5), dlvl=2, clvl=3), view)
        brain.trail = [(5, 5), (6, 5), (5, 5), (6, 5), (5, 5)]
        back = Decision(DIRS[(-1, 0)], "explore", "back again")
        decision = brain.break_oscillation(command_obs(pos=(6, 5), dlvl=2, clvl=3), view, back)
        self.assertIn((5, 5), brain.level.bumped)
        self.assertNotEqual(decision.key, DIRS[(-1, 0)])

    def test_the_same_square_ending_loops_again_is_blocked_longer(self) -> None:
        """2026-11-03 A/B: blocked 10 steps each time, a rest/explore loop
        resumed 250,000 times. Each repeat on the same square doubles the block."""
        from moria_playtest.brain import BUMP_STEPS, Decision
        brain = Brain(GOALS["reach_dl2"])
        view = town_view((6, 5), (40, 40), dlvl=2)
        brain.track(command_obs(pos=(6, 5), dlvl=2, clvl=3), view)
        blocks = []
        for n in range(4):
            o = command_obs(pos=(6, 5), dlvl=2, clvl=3)
            o.step = 1000 * (n + 1)
            brain.trail = [(5, 5), (6, 5), (5, 5), (6, 5), (5, 5)]
            brain.break_oscillation(o, town_view((6, 5), (40, 40), dlvl=2), Decision(DIRS[(-1, 0)], "explore", "back again"))
            blocks.append(brain.level.bumped[(5, 5)] - o.step)
        self.assertEqual(blocks, [BUMP_STEPS, 2 * BUMP_STEPS, 4 * BUMP_STEPS, 8 * BUMP_STEPS])

    def test_a_longer_circuit_is_blocked_and_rechosen(self) -> None:
        """M6, C128 seed 1002: an 8-square lap toward the up stairs, walked
        2,300 times until the Warrior starved."""
        from moria_playtest.brain import Decision
        brain = Brain(GOALS["reach_dl2"])
        lap = [(11, 6), (11, 7), (11, 8), (12, 9), (12, 10), (12, 9), (12, 8), (11, 7)]   # the lap, shifted
        brain.track(command_obs(pos=lap[0], dlvl=2, clvl=3), town_view(lap[0], (30, 15), dlvl=2))
        for i in range(4 * len(lap)):
            here, there = lap[i % len(lap)], lap[(i + 1) % len(lap)]
            on = Decision(DIRS[(there[0] - here[0], there[1] - here[1])], "resupply", "up stairs")
            decision = brain.break_oscillation(command_obs(pos=here, dlvl=2, clvl=3),
                                               town_view(here, (30, 15), dlvl=2), on)
            if decision is not on:
                break
        self.assertGreaterEqual(i, len(lap))         # the first lap is walked as chosen
        self.assertIsNot(decision, on)               # and the circuit is broken within four
        self.assertIn(there, brain.level.bumped)     # by blocking the square it would enter again

    def test_walking_on_through_a_room_is_not_a_circuit(self) -> None:
        from moria_playtest.brain import Decision
        brain = Brain(GOALS["reach_dl2"])
        brain.track(command_obs(pos=(5, 5), dlvl=2, clvl=3), town_view((5, 5), (30, 15), dlvl=2))
        east = Decision(DIRS[(1, 0)], "explore", "on")
        for x in range(1, 39):   # moves east, every square new
            self.assertIs(brain.break_oscillation(command_obs(pos=(x, 5), dlvl=2, clvl=3),
                                                  town_view((x, 5), (30, 15), dlvl=2), east), east)

    def test_a_potion_between_the_flips_still_counts(self) -> None:
        """M5a round 7: a drink every few steps beside a Yellow Jelly put
        the same square in the trail twice and hid the oscillation."""
        from moria_playtest.brain import Decision
        brain = Brain(GOALS["reach_dl2"])
        left, right = town_view((5, 5), (40, 40), dlvl=2), town_view((6, 5), (40, 40), dlvl=2)
        brain.track(command_obs(pos=(5, 5), dlvl=2, clvl=3), left)
        go_right, go_left = Decision(DIRS[(1, 0)], "explore", "on"), Decision(DIRS[(-1, 0)], "hunt", "back")
        quaff = Decision(ord("q"), "quaff", "drink")
        at_left, at_right = command_obs(pos=(5, 5), dlvl=2, clvl=3), command_obs(pos=(6, 5), dlvl=2, clvl=3)
        for _ in range(2):
            brain.break_oscillation(at_left, left, go_right)
            brain.break_oscillation(at_right, right, quaff)        # a drink between the steps
            brain.break_oscillation(at_right, right, go_left)
        brain.break_oscillation(at_left, left, go_right)
        decision = brain.break_oscillation(at_right, right, go_left)
        self.assertIn((5, 5), brain.level.bumped)
        self.assertNotEqual(decision.key, DIRS[(-1, 0)])

    def test_moving_on_is_untouched(self) -> None:
        from moria_playtest.brain import Decision
        brain = Brain(GOALS["reach_dl2"])
        view = town_view((6, 5), (40, 40), dlvl=2)
        brain.trail = [(3, 5), (4, 5), (5, 5), (6, 5), (5, 5)]
        on = Decision(DIRS[(-1, 0)], "explore", "x")
        self.assertIs(brain.break_oscillation(command_obs(pos=(6, 5), dlvl=2, clvl=3), view, on), on)


class PotionTest(unittest.TestCase):
    """M4 round 39 (§15.5): stores identify their stock (as VMS store_carry
    does), so the Alchemist sells Cure Light Wounds by name."""

    def test_climbing_home_does_not_lower_the_food_reserve(self) -> None:
        """M4 round 55: at DL3 2.33 rations was too little (go up), at DL2
        enough (go down): one staircase each way per step."""
        brain = Brain(GOALS["reach_dl2"])
        brain.food = 2.33
        brain.track(command_obs(pos=(5, 5), dlvl=3, clvl=5), town_view((5, 5), (40, 40), dlvl=3))
        self.assertTrue(brain.food_low())
        brain.track(command_obs(pos=(5, 5), dlvl=2, clvl=5), town_view((5, 5), (40, 40), dlvl=2))
        self.assertTrue(brain.food_low())
        brain.track(command_obs(pos=(5, 5), dlvl=0, clvl=5), town_view((5, 5), (40, 40), dlvl=0))
        self.assertEqual(brain.food_reserve(), 1)            # back to the shallow reserve (M5b round 35)

    def test_a_bigger_map_keeps_more_food(self) -> None:
        """M6: on the 80-column ports' 198x66 maps the walk home is longer;
        the C64's reserve starved 53 of the C128's 66 deaths on DL1-2."""
        brain = Brain(GOALS["reach_dl2"])
        brain.track(command_obs(pos=(5, 5), dlvl=1, clvl=5), town_view((5, 5), (40, 40), dlvl=1))
        self.assertEqual(brain.food_reserve(), 1)            # the C64's 80x48: unchanged
        brain.clvl = 1
        self.assertEqual(brain.food_max(), 8)
        big = View(198, 66, [0] * (198 * 66), (5, 5), 1, {})
        brain.track(command_obs(pos=(5, 5), dlvl=1, clvl=5), big)
        self.assertEqual(brain.food_reserve(), 4)            # 3.4 times the area
        brain.food = 3
        self.assertTrue(brain.food_low())
        big = View(198, 66, [0] * (198 * 66), (5, 5), 6, {})
        brain.track(command_obs(pos=(5, 5), dlvl=6, clvl=5), big)
        self.assertEqual(brain.food_reserve(), 14)           # (2 + 6 // 3) * 3.4, rounded up
        brain.clvl = 1
        self.assertEqual(brain.food_max(), 28)               # the early eight, 3.4 times
        brain.lamp, brain.oil, brain.torches, brain.lamp_packed, brain.light_left = True, 0, 0, False, 5000
        self.assertTrue(brain.light_low())                   # 2,000 turns of light home on the C64's map
        brain.track(command_obs(pos=(5, 5), dlvl=1, clvl=5), town_view((5, 5), (40, 40), dlvl=1))
        self.assertFalse(brain.light_low())

    def test_deep_without_a_lantern_it_carries_more_torches_and_seeks_one(self) -> None:
        """2026-11-09: level-37 Priests with no lantern lit torches and went
        home by Word of Recall for more every 4,000 steps on DL37."""
        from moria_playtest.brain import BLACK_MARKET, LANTERN, TORCH, TORCH_RESERVE, TORCH_RESERVE_DEEP
        brain = Brain(GOALS["deep"])
        brain.clvl, brain.max_dlvl, brain.torches = 37, 37, TORCH_RESERVE
        self.assertEqual(brain.torch_reserve(), TORCH_RESERVE_DEEP)
        self.assertIn(TORCH, brain.shopping_list())
        self.assertIn(LANTERN, brain.shopping_list())
        brain.at_store, brain.gold_seen = BLACK_MARKET, 10_000_000
        self.assertIn(LANTERN, brain.shopping_list(10_000_000))       # the Black Market's too, rich
        brain.lamp = True
        self.assertEqual(brain.torch_reserve(), TORCH_RESERVE)        # with a lantern: the backup only

    def test_food_shopping_leaves_pack_room(self) -> None:
        """M4 round 54: items never stack, and 20 single foods filled the
        pack so Word of Recall could not be bought (seed 1020)."""
        brain = Brain(GOALS["reach_dl2"])
        brain.food = 1
        self.assertIn("Slime Mold", brain.shopping_list())         # below the reserve
        brain.food = 5
        self.assertIn("Ration of Food", brain.shopping_list())
        self.assertNotIn("Slime Mold", brain.shopping_list())      # well over the reserve: rations only
        brain.food = FOOD_MAX
        self.assertNotIn("Ration of Food", brain.shopping_list())  # carrying enough

    def test_wants_cure_light_wounds(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        brain.shop_buys, brain.torches, brain.oil = FOOD_PER_VISIT, 2, 3
        self.assertIn("Potion of Cure Light", brain.shopping_list())

    def test_early_gear_before_recall(self) -> None:
        """M5b round 6: a level-1 Paladin spent 480 of 570 gold on two Word
        of Recall scrolls and met DL1 Kobolds with a Dagger."""
        brain = Brain(GOALS["reach_dl8"])
        view = town_view((5, 5), (40, 40), dlvl=0)
        view.stores = [(2, 2), (3, 2), (8, 5), (4, 2), (5, 2), (7, 2), (5, 9)]   # Weaponsmith east
        brain.track(command_obs(pos=(5, 5), dlvl=0, clvl=1), view)
        brain.shopped = True
        o = command_obs(pos=(5, 5), dlvl=0, clvl=1)
        o.rows[23] = "HP:16/16  MP:6/6   AC:4  AU:570   Full  "
        brain.magic.study_due, brain.magic.listed = False, True
        decision = brain.decide(o, view)
        self.assertEqual((decision.layer, brain.at_store), ("shop", 2))
        self.assertEqual(brain.recall_reserve(), 1)

    def test_poisoned_without_a_potion_goes_to_the_temple_first(self) -> None:
        """M5 regression, seed 1002: a Half-Elf Rogue gassed on DL1 climbed
        to town at 8 HP with 132 gold and no potion, and poison killed it on
        the walk to the Weaponsmith."""
        brain = Brain(GOALS["reach_dl8"])
        view = town_view((5, 5), (40, 40), dlvl=0)
        view.stores = [(2, 2), (3, 2), (8, 5), (5, 9), (4, 2)]   # Weaponsmith east, Temple south
        brain.track(command_obs(pos=(5, 5), dlvl=0, clvl=1), view)
        brain.shopped = True
        brain.poisoned = True
        o = command_obs(pos=(5, 5), dlvl=0, clvl=1)
        o.rows[23] = "HP:8/22   MP:0/0   AC:9  AU:132   Full  "
        brain.magic.study_due, brain.magic.listed = False, True
        decision = brain.decide(o, view)
        self.assertEqual((decision.layer, decision.key, brain.at_store), ("shop", DIRS[(0, 1)], 3))
        self.assertIn("Potion of Cure Light", brain.shopping_list())
        brain.at_store, brain.poisoned = None, False                 # cured: the early gear order again
        self.assertEqual((brain.decide(o, view).layer, brain.at_store), ("shop", 2))

    def test_the_temple_after_the_general_store(self) -> None:
        # Level 5: past the early gear-first order (M5b round 6).
        brain = Brain(GOALS["reach_dl2"])
        view = town_view((5, 5), (40, 40), dlvl=0)
        view.stores = [(2, 2), (3, 2), (4, 2), (9, 5), (5, 2)]   # Temple east
        brain.track(command_obs(pos=(5, 5), dlvl=0, clvl=5), view)   # in town
        brain.shopped = True                                         # General Store done
        brain.phase = 3                                              # no Alchemist trip for Phase Door
        poor = command_obs(pos=(5, 5), dlvl=0, clvl=5)
        poor.rows[23] = "HP:21/21  MP:0/0   AC:4  AU:15    Full  "
        self.assertNotEqual(brain.decide(poor, view).layer, "shop")  # round 45: not worth the walk
        rich = command_obs(pos=(5, 5), dlvl=0, clvl=5)
        rich.rows[23] = "HP:21/21  MP:0/0   AC:4  AU:300   Full  "
        brain.recall = 2                                             # Word of Recall would come first
        decision = brain.decide(rich, view)
        self.assertEqual((decision.layer, decision.key), ("shop", DIRS[(1, 0)]))
        self.assertEqual(brain.at_store, 3)

    def test_the_black_market_for_word_of_recall_when_rich(self) -> None:
        """M4 round 48: the Temple rarely stocks Word of Recall; drops
        (MON-014) pay the Black Market's prices."""
        brain = Brain(GOALS["reach_dl2"])
        view = town_view((5, 5), (40, 40), dlvl=0)
        view.stores = [(2, 2), (3, 2), (4, 2), (5, 2), (6, 2), (7, 2), (5, 9)]   # Black Market south
        brain.track(command_obs(pos=(5, 5), dlvl=0, clvl=5), view)
        brain.shopped = brain.potions_done = brain.alchemist_done = True   # the Alchemist had none
        rich = command_obs(pos=(5, 5), dlvl=0, clvl=5)
        rich.rows[23] = "HP:21/21  MP:0/0   AC:4  AU:900   Full  "
        decision = brain.decide(rich, view)
        self.assertEqual((decision.layer, decision.key), ("shop", DIRS[(0, 1)]))
        self.assertEqual(brain.shopping_list(), ["Scroll of Word of Rec"])
        brain.recall = 2                                     # RECALL_RESERVE
        brain.at_store = None
        brain.weapons_done = brain.armoury_done = True       # gear is bought with what is left
        brain.magic_done = True                              # and a wand or staff (2026-11-04)
        self.assertNotEqual(brain.decide(rich, view).layer, "shop")

    def test_a_stack_is_picked_by_name(self) -> None:
        """Items stack (VMS inven_carry): the list shows "3 Potion of ..."."""
        brain = Brain(GOALS["reach_dl2"])
        brain.food, brain.clw = 3, 3
        view = town_view((5, 5), (40, 40), dlvl=3, monsters={(6, 5)})
        brain.decide(command_obs(pos=(5, 5), dlvl=3, clvl=5, hp=10, mhp=60), view)
        listed = command_obs(pos=(5, 5), rows={1: " a) 4 Ration of Food", 2: " b) 3 Potion of Cure Light Wounds"})
        listed.mode, listed.stage = Mode.ITEM, "list"
        self.assertEqual(brain.decide(listed, None).key, ord("B"))

    def test_badly_hurt_drinks_one(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        brain.food, brain.clw = 3, 2
        view = town_view((5, 5), (40, 40), dlvl=3, monsters={(6, 5)})
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=3, clvl=5, hp=10, mhp=60), view)
        self.assertEqual((decision.layer, decision.key), ("quaff", ord("Q")))
        prompt = command_obs(pos=(5, 5), rows={0: "Quaff which potion (a-a)?"})   # round 40: not "item"
        prompt.mode, prompt.stage = Mode.ITEM, "which"
        self.assertEqual(brain.decide(prompt, None).key, ord("?"))
        listed = command_obs(pos=(5, 5), rows={1: " a) Ration of Food", 2: " b) 2 Potion of Cure Light Wounds"})
        listed.mode, listed.stage = Mode.ITEM, "list"
        self.assertEqual(brain.decide(listed, None).key, ord("B"))
        self.assertEqual(brain.clw, 1)   # the two listed, one drunk


class GropeTest(unittest.TestCase):
    """M4 round 43 (§15.5): frontier squares that revealed nothing are felt
    into, one unknown neighbour at a time, before resting."""

    def test_feels_into_the_dark_before_resting(self) -> None:
        brain = Brain(GOALS["clvl5"])
        brain.food = 3
        view = UnstuckTest.corridor(UnstuckTest(), 2, (40, 40), unknown_behind=True)
        view.types[5 * COLS + 10] = WALL
        view.types[5 * COLS + 11] = UNKNOWN                  # dark beyond the corridor end
        view.types[40 * COLS + 40] = 0x0                     # no stairs
        brain.track(command_obs(pos=(10, 5), dlvl=2, clvl=5), view)
        view.pos = (10, 5)
        view.types[5 * COLS + 10] = 0x0
        brain.level.dead_frontier |= view.frontier(traps=True)
        brain.level.searches = {spot: 99 for spot in view.search_spots(set())}
        decision = brain.decide(command_obs(pos=(10, 5), dlvl=2, clvl=5), view)
        self.assertEqual((decision.layer, decision.key), ("grope", DIRS[(1, 0)]))
        self.assertIn((11, 5), brain.level.groped)


class GearTest(unittest.TestCase):
    """M4 round 74: characters met Green Nagas on DL5-9 with the starting
    Dagger and AC 4, carrying thousands of gold (maintainer direction
    2026-10-23: build up first)."""

    def store(self, brain, store, items, gold):
        brain.at_store = store
        rows = {0: "Store", 19: f" B)uy  S)ell  Q)uit  Gold: {gold}"}
        rows.update({3 + i: f" {chr(97 + i)}) {name:<26}{price:>4} GP" for i, (name, price) in enumerate(items)})
        o = BrainM2Test.store_obs(BrainM2Test(), "menu", rows)
        o.rows[22] = "ST:18  IN: 6  WI:11  DX:12  CO:14  CH: 6"
        return o

    def test_rich_it_buys_the_ring_and_amulet_worth_most_and_wears_them(self) -> None:
        """2026-11-07: a level-34 Priest with 4,000K gold wore no ring or
        amulet (maintainer: "max out all of its stats and equipment")."""
        from moria_playtest.brain import MAGIC_SHOP
        from moria_playtest.goals import for_character
        brain = Brain(for_character(GOALS["deep"], "half-troll-priest"))
        brain.clvl = 34
        self.assertEqual([brain.jewel_value(n) for n in ("Ring of Protection [+7]", "Ring of Strength (+3)",
                                                         "Amulet of Wisdom (+2)", "Ring of Speed",
                                                         "Ring of Strength (-2)", "Amulet of the Magi")],
                         [70, 0, 40, 1000, -1, 300])
        brain.jewels = {"Ring": 30, "Amulet": 0}
        o = self.store(brain, MAGIC_SHOP, [("Ring of Protection [+7]", 700), ("Ring of Strength (+3)", 1200),
                                           ("Amulet of Wisdom (+2)", 900), ("Wand of Light (8 charges)", 200)], 900000)
        self.assertEqual(brain.jewel_pick(o), ("a", "Ring of Protection [+7]"))   # +40 over +30 worn
        # bought: the next pick counts it as going on the free right hand, so
        # a ring now goes on the left (two hands, VMS moria.inc:528); the
        # store no longer lists the one bought, and the amulet gains most
        brain.credit("Ring of Protection [+7]", 1)
        self.assertEqual(brain.jewel_slot("Ring"), "Ring2")
        o = self.store(brain, MAGIC_SHOP, [("Ring of Strength (+3)", 1200), ("Amulet of Wisdom (+2)", 900),
                                           ("Wand of Light (8 charges)", 200)], 900000)
        self.assertEqual(brain.jewel_pick(o), ("b", "Amulet of Wisdom (+2)"))
        self.assertEqual(brain.to_wear, ["Ring of Protection [+7]"])

    def test_two_ring_hands_are_read_and_a_ring_judged_by_the_one_it_replaces(self) -> None:
        """2026-11-08: two ring hands (VMS moria.inc:528): a ring goes on the
        right hand when free, else on the left, replacing its ring."""
        brain = Brain(GOALS["deep"])
        rows = ["Equipment", " h) Ring:   Ring of Speed", " i) Amulet: Amulet of the Magi", "    Ring:   (none)"]
        self.assertEqual(brain.read_jewels(rows), {"Ring": 1000, "Amulet": 300, "Ring2": 0})
        self.assertEqual(brain.jewel_slot("Ring"), "Ring2")                       # the right hand is taken
        self.assertTrue(brain.jewel_better("Ring of Resist Cold"))               # the free left hand
        rows[3] = " j) Ring:   Ring of Resist Fire"
        brain.jewels = brain.read_jewels(rows)
        self.assertEqual(brain.jewel_names["Ring2"], "Ring of Resist Fire")
        self.assertFalse(brain.jewel_better("Ring of Resist Cold"))              # no better than the left's
        self.assertEqual(brain.resist_div(command_obs(pos=(5, 5), dlvl=30), "fire", lasting=True), 3)

    def test_an_ego_weapon_is_valued_and_bought(self) -> None:
        """2026-11-07: "Dagger (Defender)" was looked up whole, scored 0 and
        never bought, millions of gold in hand."""
        from moria_playtest.brain import BLACK_MARKET
        brain = Brain(GOALS["deep"])
        brain.weapon = ("Mace", 3)
        o = self.store(brain, BLACK_MARKET, [("Mace (Slay Evil) (+3,+3)", 9000), ("Mace (+3,+3)", 400)], 900000)
        self.assertGreater(brain.melee_value("Mace (Slay Evil)", 3, o), 1.4 * brain.melee_value("Mace", 3, o))
        self.assertEqual(brain.gear_pick(o), ("a", "Mace (Slay Evil) (+3,+3)"))
        self.assertGreater(brain.melee_value("Mace (Frost)", 3, o), brain.melee_value("Mace", 3, o))   # Frost Brand too

    def test_the_ring_and_amulet_worn_are_read_from_the_equipment_list(self) -> None:
        from moria_playtest.goals import for_character
        brain = Brain(for_character(GOALS["deep"], "human-warrior"))
        rows = ["Equipment", " a) Weapon: Dagger (+1,+1)", " h) Ring:   Ring of Strength", "            (+2)",
                " i) Amulet: (none)"]
        self.assertEqual(brain.read_jewels(rows), {"Ring": 30, "Amulet": 0})

    def test_gold_shown_in_thousands_is_read_in_full(self) -> None:
        """2026-11-06: 40 columns show 100,000 and up as "AU:739K", read as
        739: rich C64 characters took no gear trips."""
        self.assertEqual(Brain.gold(command_obs(rows={23: "HP:68/68  MP:30/30 AC:4  AU:739K  Full"})), 739000)
        self.assertEqual(Brain.gold(command_obs(rows={23: "HP:68/68  MP:30/30 AC:4  AU:12288 Full"})), 12288)

    def test_rich_buys_enchant_armor_and_reads_it_in_town(self) -> None:
        from moria_playtest.brain import ALCHEMIST, ENCHANT_ARMOR, ENCHANT_PER_VISIT, ENCHANT_PER_VISIT_RICH
        brain = Brain(GOALS["deep"])
        brain.clvl, brain.ac_seen = 26, 12
        brain.at_store = ALCHEMIST
        self.assertIn(ENCHANT_ARMOR, brain.shopping_list(300000))
        self.assertNotIn(ENCHANT_ARMOR, brain.shopping_list(5000))          # not when poor
        brain.ac_seen = 60
        self.assertNotIn(ENCHANT_ARMOR, brain.shopping_list(300000))        # nor well armoured
        brain.ac_seen = 12
        for _ in range(ENCHANT_PER_VISIT):
            brain.credit(ENCHANT_ARMOR, 1)
        self.assertNotIn(ENCHANT_ARMOR, brain.shopping_list(40000))         # a visit's worth
        self.assertIn(ENCHANT_ARMOR, brain.shopping_list(300000))           # rich: what is stocked (2026-11-07)
        for _ in range(ENCHANT_PER_VISIT_RICH - ENCHANT_PER_VISIT):
            brain.credit(ENCHANT_ARMOR, 1)
        self.assertNotIn(ENCHANT_ARMOR, brain.shopping_list(300000))
        view = town_view((5, 5), (40, 40), dlvl=0)
        o = command_obs(pos=(5, 5), dlvl=0, clvl=26)
        decision = brain.read_enchantments(o, view)
        self.assertEqual((decision.key, brain.picking), (ord("R"), ENCHANT_ARMOR))

    def test_rich_shops_the_black_market_for_armour(self) -> None:
        from moria_playtest.brain import BLACK_MARKET
        brain = Brain(GOALS["deep"])
        brain.armour = {"ICAT_ARMOR": 9, "ICAT_SHIELD": 3, "ICAT_HELM": 2, "ICAT_GLOVES": 1, "ICAT_BOOTS": 2}
        rich = self.store(brain, BLACK_MARKET, [("Potion of Speed", 900), ("Plate Mail [9,+6]", 9000)], 300000)
        decision = brain.decide(rich, None)
        self.assertEqual((decision.key, brain.buying), (ord("B"), "Plate Mail [9,+6]"))
        poor = self.store(Brain(GOALS["deep"]), BLACK_MARKET, [("Plate Mail [9,+6]", 9000)], 20000)
        self.assertNotEqual(Brain(GOALS["deep"]).decide(poor, None).reason, "buy Plate Mail [9,+6]")

    def test_armour_leaves_the_price_of_a_weapon_while_the_dagger_is_wielded(self) -> None:
        """M5b round 36b: 13 of 15 deaths at level 1-3 still held the starting
        Dagger, the gold spent at the Armoury."""
        brain = Brain(GOALS["reach_dl8"])
        o = self.at_level(self.store(brain, 1, [("Hard Leather Armor [6,+1]", 140)], 230), 1)
        brain.decide(o, None)
        self.assertIsNone(brain.store_letter)                # 230 - 40 - 110 leaves 80
        brain = Brain(GOALS["reach_dl8"])
        brain.weapon = ("Mace", 0)
        brain.decide(self.at_level(self.store(brain, 1, [("Hard Leather Armor [6,+1]", 140)], 230), 1), None)
        self.assertEqual(brain.store_letter, "a")

    def test_a_mage_buys_potions_not_weapons(self) -> None:
        """M5f: Elf and Halfling Mages bought a Tulwar, a Spear, a shield,
        boots and gloves, left town with two potions, and died to DL1
        Kobolds and poison gas holding none."""
        from moria_playtest import goals
        mage = lambda: Brain(goals.for_character(GOALS["reach_dl8"], "elf-mage"))
        brain = mage()
        brain.decide(self.at_level(self.store(brain, 2, [("Main Gauche (+2,+2)", 429), ("Spear", 40)], 900), 1), None)
        self.assertIsNone(brain.store_letter)                     # no weapon at the Weaponsmith
        brain = mage()
        brain.decide(self.at_level(self.store(brain, 1, [("Hard Leather Armor [6,+1]", 140)], 230), 1), None)
        self.assertIsNone(brain.store_letter)                     # 230 - 5 potions x 20 leaves 130
        brain = mage()
        brain.clw = 5
        brain.decide(self.at_level(self.store(brain, 1, [("Hard Leather Armor [6,+1]", 140)], 230), 1), None)
        self.assertEqual(brain.store_letter, "a")                 # potions held; no weapon gold kept back
        priest = Brain(goals.for_character(GOALS["reach_dl8"], "gnome-priest"))
        self.assertGreaterEqual(priest.gear_reserve(self.at_level(self.store(priest, 1, [], 230), 1)), 100)   # round 12

    def test_a_slot_just_bought_for_is_not_bought_again(self) -> None:
        """M5a: bought, not yet worn, counts as worn; the next piece goes to
        another slot."""
        brain = Brain(GOALS["reach_dl8"])
        stock = [("Hard Leather Armor [6,+2]", 300), ("Studded Leather Armor [5,+2]", 250),
                 ("Iron Helm [1,+0]", 80)]                       # +4, +3 and +1 over Leather Armor [4]
        brain.decide(self.store(brain, 1, stock, 1200), None)
        self.assertEqual(brain.store_letter, "a")                 # the biggest gain, on the body
        brain.count_purchase()
        brain.decide(self.store(brain, 1, stock[1:], 900), None)
        self.assertEqual(brain.store_letter, "b")                 # the helm, not a second body armour

    def test_gold_for_armour_is_a_town_trip(self) -> None:
        """M5a: a Half-Elf on DL5 carried 1,547 gold in AC 7; town trips came
        only for food, light or Word of Recall."""
        brain = Brain(GOALS["reach_dl8"])
        brain.food, brain.recall = 10, 2
        rich = command_obs(pos=(5, 5), dlvl=5, clvl=7, hp=70, mhp=70,
                           rows={23: "HP:70/70  MP:0/0   AC:7  AU:1547"})
        self.assertTrue(brain.needs_resupply(rich))
        poor = command_obs(pos=(5, 5), dlvl=5, clvl=7, hp=70, mhp=70,
                           rows={23: "HP:70/70  MP:0/0   AC:7  AU:600"})
        self.assertFalse(brain.needs_resupply(poor))
        brain.track(command_obs(pos=(5, 5), dlvl=0), town_view((5, 5), (40, 40)))   # just been to town
        rich.step = 100
        self.assertFalse(brain.needs_resupply(rich))

    def test_blows_follow_the_game_table(self) -> None:
        self.assertEqual(knowledge.blows(18, 12, 12), 2)    # Dagger, 1.2 lb
        self.assertEqual(knowledge.blows(18, 12, 200), 1)   # Two-Handed Sword, 20 lb

    def test_the_weapon_with_the_most_damage_a_turn_is_bought(self) -> None:
        brain = Brain(GOALS["reach_dl8"])
        o = self.store(brain, 2, [("Main Gauche (+2,+2)", 429), ("Two-Handed Sword (+1,+1)", 408),
                                  ("Awl-Pike", 92)], 900)
        decision = brain.decide(o, None)
        self.assertEqual((decision.key, brain.store_letter), (ord("B"), "b"))   # 1 x (10.5 + 1) beats 2 x (3 + 2)

    def test_a_weak_character_buys_a_weapon_it_can_swing(self) -> None:
        """M5b round 16: a Human Priest (ST 10) bought by damage alone; a
        Two-Handed Sword (20 lb) over STR x 15 costs 3 to-hit a point
        (core/combat.s), and it hit DL1 Kobolds 42% of the time."""
        brain = Brain(GOALS["reach_dl8"])
        o = self.store(brain, 2, [("Mace", 130), ("Two-Handed Sword", 230)], 900)
        o.rows[22] = "ST:10  IN: 9  WI:16  DX:10  CO:12  CH:12"
        brain.decide(o, None)
        self.assertNotEqual(brain.store_letter, "b")                   # never the sword it cannot swing
        brain = Brain(GOALS["reach_dl8"])
        o = self.store(brain, 2, [("Mace", 130), ("Two-Handed Sword", 230)], 900)
        o.rows[22] = "ST:18  IN: 9  WI:16  DX:10  CO:12  CH:12"     # strong enough for either
        brain.decide(o, None)
        self.assertEqual(brain.store_letter, "b")

    @staticmethod
    def at_level(o, clvl: int):
        zp = bytearray(o.zp)
        zp[0x33] = clvl
        return dataclasses.replace(o, zp=bytes(zp))

    def test_only_what_the_gold_allows_over_the_reserve(self) -> None:
        brain = Brain(GOALS["reach_dl8"])
        o = self.at_level(self.store(brain, 2, [("Main Gauche (+2,+2)", 429), ("Short Sword (+1,+1)", 229)], 500), 5)
        brain.decide(o, None)
        self.assertEqual(brain.store_letter, "b")

    def test_a_level_1_character_keeps_a_small_reserve(self) -> None:
        """M5b round 5: a level-1 Priest left town with 175 gold unspent, a
        Dagger and Leather Armour, under the 200 reserve."""
        brain = Brain(GOALS["reach_dl8"])
        o = self.at_level(self.store(brain, 2, [("Morningstar", 120)], 175), 1)   # 2d6: one blow beats two of the Dagger
        brain.decide(o, None)
        self.assertEqual(brain.store_letter, "a")
        brain = Brain(GOALS["reach_dl8"])
        o = self.at_level(self.store(brain, 2, [("Morningstar", 120)], 175), 5)
        brain.decide(o, None)
        self.assertIsNone(brain.store_letter)

    def test_armour_buys_the_biggest_gain_in_a_slot_and_is_worn_in_town(self) -> None:
        brain = Brain(GOALS["reach_dl8"])
        o = self.store(brain, 1, [("Leather Armor [4,+1]", 134), ("Metal Cap [1,+2]", 258),
                                  ("Robe [2,+1]", 117)], 600)
        brain.decide(o, None)
        self.assertEqual(brain.store_letter, "b")            # +3 on the head beats +1 on the body
        brain.count_purchase()
        self.assertEqual(brain.to_wear, ["Metal Cap [1,+2]"])
        view = town_view((5, 5), (40, 40), dlvl=0)
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=0, clvl=3), view)
        self.assertEqual((decision.layer, decision.key, brain.picking), ("wear", KEY_WEAR, "Metal Cap [1,+2]"))
        self.assertNotIn("ICAT_HELM", brain.armour)           # worn only once picked from the pack
        listed = BrainM2Test.store_obs(BrainM2Test(), "list", {1: " a) Metal Cap [1,+2]"})
        listed.mode = Mode.ITEM
        self.assertEqual(brain.decide(listed, None).key, ord("A"))
        self.assertEqual(brain.armour["ICAT_HELM"], 3)

    def test_a_refused_purchase_is_not_worn(self) -> None:
        brain = Brain(GOALS["reach_dl8"])
        brain.decide(self.store(brain, 1, [("Metal Cap [1,+2]", 258)], 600), None)
        brain.count_purchase()
        refused = self.store(brain, 1, [("Metal Cap [1,+2]", 258)], 600)
        refused.stage = "message"
        brain.decide(refused, None)
        self.assertEqual((brain.to_wear, brain.armour.get("ICAT_HELM")), ([], None))

    def test_nothing_better_leaves(self) -> None:
        brain = Brain(GOALS["reach_dl8"])
        o = self.store(brain, 1, [("Robe [2,+1]", 117)], 600)
        self.assertEqual(brain.decide(o, None).key, ord("Q"))
        self.assertTrue(brain.armoury_done)


class RecallTest(unittest.TestCase):
    """M4 round 44 (§15.5): Word of Recall to town and back instead of the
    stairs (reach_dl10 starved hunting up staircases)."""

    def test_stuck_on_a_level_reads_one_whatever_the_food(self) -> None:
        """M4 rounds 78-80: characters searched or wandered a level until they
        starved."""
        brain = Brain(GOALS["reach_dl8"])
        brain.food, brain.recall, brain.torches, brain.oil = 12, 1, 2, 3
        view = town_view((5, 5), (40, 40), dlvl=2)
        brain.track(command_obs(pos=(5, 5), dlvl=2, clvl=6), view)
        o = command_obs(pos=(5, 5), dlvl=2, clvl=6)
        self.assertIsNone(brain.recall_trip(o, view))         # fed and making progress: no
        brain.level.since_progress = STUCK_STEPS
        self.assertEqual(brain.recall_trip(o, view).key, ord("R"))

    def test_deep_and_short_of_food_reads_one(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        brain.food, brain.recall = 0, 1
        view = town_view((5, 5), (40, 40), dlvl=5)
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=5, clvl=8), view)
        self.assertEqual((decision.layer, decision.key), ("recall", ord("R")))
        listed = command_obs(pos=(5, 5), rows={1: " a) Ration of Food", 2: " b) Scroll of Word of Recall"})
        listed.mode, listed.stage = Mode.ITEM, "list"
        self.assertEqual(brain.decide(listed, None).key, ord("B"))
        self.assertTrue(brain.recalling)
        waiting = brain.decide(command_obs(pos=(5, 5), dlvl=5, clvl=8), town_view((5, 5), (40, 40), dlvl=5))
        self.assertEqual((waiting.layer, waiting.key), ("recall", ord("5")))

    def test_in_town_after_shopping_reads_one_to_go_back(self) -> None:
        """Two scrolls: one to go back, one kept for the way home (M5a; one
        was read until then)."""
        brain = Brain(GOALS["reach_dl2"])
        brain.food, brain.recall, brain.max_dlvl, brain.torches, brain.oil = 6, 2, 6, 2, 3
        view = town_view((5, 5), (40, 40), dlvl=0)
        brain.track(command_obs(pos=(5, 5), dlvl=0, clvl=8), view)
        brain.shopped = brain.potions_done = brain.weapons_done = brain.armoury_done = True
        brain.alchemist_done = True
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=0, clvl=8), view)
        self.assertEqual((decision.layer, decision.key), ("recall", ord("R")))

    def test_in_town_reads_one_when_the_temple_was_not_worth_a_visit(self) -> None:
        """C128 catalog cycle, 2026-11-02: readiness waited on a Temple visit
        that shopping never made with potions enough, so characters holding
        two scrolls walked down from DL1 (82 recalls up, 11 down)."""
        brain = Brain(GOALS["reach_dl2"])
        brain.food, brain.recall, brain.max_dlvl, brain.torches, brain.oil = 6, 2, 6, 2, 3
        brain.clw = brain.clw_reserve()
        view = town_view((5, 5), (40, 40), dlvl=0)
        view.stores = [(2, 2), (3, 2), (4, 2), (5, 2), (8, 5), (7, 2), (5, 9), (9, 9)]   # a Temple in town
        o = command_obs(pos=(5, 5), dlvl=0, clvl=8, rows={23: "HP:60/60  MP:0/0   AC:20  AU:100"})
        brain.track(o, view)
        brain.shopped = brain.weapons_done = brain.armoury_done = brain.alchemist_done = True
        self.assertFalse(brain.potions_done or brain.temple_worth_it(o))
        decision = brain.recall_trip(o, view)
        self.assertEqual((decision.layer, decision.key), ("recall", ord("R")))

    def test_gold_alone_waits_for_more_after_a_visit_that_bought_no_gear(self) -> None:
        """C128 catalog cycle, 2026-11-02: a clvl-24 Half-Orc with 22,000 gold
        recalled up every 5,000 steps and the stores had nothing better."""
        brain = Brain(GOALS["deep"])
        rich = command_obs(pos=(5, 5), dlvl=0, clvl=24, rows={23: "HP:60/60  MP:0/0   AC:20  AU:22000"})
        brain.track(rich, town_view((5, 5), (40, 40), dlvl=0))
        brain.armoury_done = brain.weapons_done = True       # both visited, nothing bought
        below = command_obs(pos=(5, 5), dlvl=1, clvl=24, rows={23: "HP:60/60  MP:0/0   AC:20  AU:22000"})
        below.step = brain.gear_trip_after
        brain.track(below, town_view((5, 5), (40, 40), dlvl=1))
        self.assertFalse(brain.wants_gear(below))
        richer = command_obs(pos=(5, 5), dlvl=1, clvl=24, rows={23: f"HP:60/60  MP:0/0   AC:20  AU:{22000 + GEAR_TRIP_GOLD}"})
        richer.step = brain.gear_trip_after
        self.assertTrue(brain.wants_gear(richer))
        brain.track(rich, town_view((5, 5), (40, 40), dlvl=0))    # the next visit buys armour
        brain.armoury_done = brain.weapons_done = brain.gear_bought = True
        brain.track(below, town_view((5, 5), (40, 40), dlvl=1))
        below.step = brain.gear_trip_after                         # the wait counts from leaving town
        self.assertTrue(brain.wants_gear(below))

    def test_each_visit_that_buys_no_gear_doubles_the_wait(self) -> None:
        """M8, 2026-11-02: a level-26 Gnome with 27,000 gold earned the next
        1,000 within 5,000 steps and went up every time, buying nothing."""
        brain = Brain(GOALS["deep"])
        waits = []
        for visit in range(3):
            town = command_obs(pos=(5, 5), dlvl=0, clvl=24, rows={23: "HP:60/60  MP:0/0   AC:20  AU:27000"})
            town.step = 100_000 * visit
            brain.track(town, town_view((5, 5), (40, 40), dlvl=0))
            brain.armoury_done = brain.weapons_done = True       # both visited, nothing bought
            below = command_obs(pos=(5, 5), dlvl=1, clvl=24, rows={23: "HP:60/60  MP:0/0   AC:20  AU:27000"})
            below.step = town.step + 100
            brain.track(below, town_view((5, 5), (40, 40), dlvl=1))
            waits.append(brain.gear_trip_after - below.step)
        self.assertEqual(waits, [2 * GEAR_TRIP_WAIT, 4 * GEAR_TRIP_WAIT, 8 * GEAR_TRIP_WAIT])

    def test_arrows_are_not_gear(self) -> None:
        """M8, 2026-11-02: arrows bought on every visit counted as gear and
        reset the gear trip's gold and wait."""
        from moria_playtest import goals
        from moria_playtest.brain import WEAPONSMITH
        rows = {19: " B)uy  S)ell  Q)uit  Gold: 27000"}
        bought = {}
        for kind, pick in (("arrows", ("a", "Arrow")), ("bow", ("b", "Long Bow")), ("sword", ("c", "Long Sword"))):
            brain = Brain(goals.for_character(GOALS["deep"], "half-orc-warrior"))
            brain.at_store = WEAPONSMITH
            brain.missile_pick = lambda obs, pick=pick: pick if kind != "sword" else None   # type: ignore[method-assign]
            brain.gear_pick = lambda obs, pick=pick: pick if kind == "sword" else None      # type: ignore[method-assign]
            self.assertEqual(brain.decide(BrainM2Test.store_obs(BrainM2Test(), "menu", rows), None).key, ord("B"))
            bought[kind] = brain.gear_bought
        self.assertEqual(bought, {"arrows": False, "bow": True, "sword": True})

    def test_no_restock_trip_straight_after_a_visit(self) -> None:
        """C128 catalog cycle, 2026-11-02: out of strong potions and Phase
        Door with 400 gold, characters recalled up every 2,600 steps to find
        the stores without them."""
        brain = Brain(GOALS["deep"])
        brain.clvl, brain.food, brain.recall, brain.torches, brain.oil = 20, 10, 2, 2, 3
        o = command_obs(pos=(5, 5), dlvl=12, clvl=20, hp=150, mhp=150,
                        rows={23: "HP:150/150  MP:0/0   AC:40  AU:450"})
        self.assertTrue(brain.needs_resupply(o))
        brain.track(command_obs(pos=(5, 5), dlvl=0, clvl=20), town_view((5, 5), (40, 40)))   # a town visit
        o.step = brain.restock_trip_after - 1
        self.assertFalse(brain.needs_resupply(o))
        o.step = brain.restock_trip_after
        self.assertTrue(brain.needs_resupply(o))

    def test_each_fruitless_restock_visit_doubles_the_wait(self) -> None:
        """M8, 2026-11-02: a level-25 Half-Troll recalled up every 5,000
        steps for Phase Door the stores did not have, 22 trips."""
        from moria_playtest.brain import GEAR_TRIP_WAIT
        brain = Brain(GOALS["deep"])
        brain.clvl, brain.food, brain.recall, brain.torches, brain.oil = 20, 10, 2, 2, 3
        waits = []
        for visit in range(3):
            town = command_obs(pos=(5, 5), dlvl=0, clvl=20)
            town.step = 100_000 * visit
            brain.track(town, town_view((5, 5), (40, 40)))
            below = command_obs(pos=(5, 5), dlvl=1, clvl=20)
            below.step = town.step + 100
            brain.track(below, town_view((5, 5), (40, 40), dlvl=1))   # left without them
            waits.append(brain.restock_trip_after - below.step)
        self.assertEqual(waits, [2 * GEAR_TRIP_WAIT, 4 * GEAR_TRIP_WAIT, 8 * GEAR_TRIP_WAIT])
        brain.strong, brain.phase = {"Potion of Cure Serious": 10}, 2   # the next visit finds them
        town.step = below.step = 400_000
        brain.track(town, town_view((5, 5), (40, 40)))
        below.step += 100
        brain.track(below, town_view((5, 5), (40, 40), dlvl=1))
        self.assertEqual(brain.restock_trip_after - below.step, GEAR_TRIP_WAIT)

    def test_waiting_for_the_yank_in_town_fights_back(self) -> None:
        """M4 round 82: seed 1023 stood waiting for Word of Recall while a
        Battle-Scarred Veteran killed it."""
        brain = Brain(GOALS["reach_dl8"])
        view = town_view((5, 5), (40, 40), dlvl=0)
        view.creatures = {(6, 5): Creature("p", 0)}
        brain.track(command_obs(pos=(5, 5), dlvl=0, clvl=6), view)
        brain.recalling = True
        hit = command_obs(pos=(5, 5), dlvl=0, clvl=6, hp=30, mhp=60,
                          rows={0: "the Battle-Scarred Veteran hits you."})
        decision = brain.decide(hit, view)
        self.assertEqual((decision.layer, decision.key), ("fight", DIRS[(1, 0)]))
        calm = command_obs(pos=(5, 5), dlvl=0, clvl=6, hp=30, mhp=60)
        self.assertEqual(brain.decide(calm, view).layer, "recall")   # not provoked: wait

    def test_the_alchemist_for_word_of_recall(self) -> None:
        """M4 round 81: most characters that starved stuck had never bought
        one; VMS stocks it at the Alchemist more often than at the Temple."""
        brain = Brain(GOALS["reach_dl8"])
        view = town_view((5, 5), (40, 40), dlvl=0)
        view.stores = [(2, 2), (3, 2), (4, 2), (5, 2), (8, 5), (7, 2), (5, 9)]   # Alchemist east
        brain.track(command_obs(pos=(5, 5), dlvl=0, clvl=5), view)
        brain.shopped = brain.potions_done = True
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=0, clvl=5), view)   # AU:277
        self.assertEqual((decision.layer, decision.key, brain.at_store), ("shop", DIRS[(1, 0)], 4))
        self.assertEqual(brain.shopping_list(), ["Scroll of Word of Rec", "Scroll of Phase Door"])

    def test_the_alchemist_for_phase_door(self) -> None:
        """M5b round 11: boxed in by breeding worms, no step out; Phase Door
        is the way out of contact (15 gp at the Alchemist)."""
        brain = Brain(GOALS["reach_dl8"])
        view = town_view((5, 5), (40, 40), dlvl=0)
        view.stores = [(2, 2), (3, 2), (4, 2), (5, 2), (8, 5), (7, 2), (5, 9)]   # Alchemist east
        brain.track(command_obs(pos=(5, 5), dlvl=0, clvl=5), view)
        brain.shopped = brain.potions_done = True
        brain.recall = 2
        poor = command_obs(pos=(5, 5), dlvl=0, clvl=5)
        poor.rows[23] = "HP:21/21  MP:0/0   AC:4  AU:30    Full  "
        decision = brain.decide(poor, view)
        self.assertEqual((decision.reason, brain.at_store), ("walk to the Alchemy shop for Phase Door", 4))
        self.assertEqual(brain.shopping_list(), ["Scroll of Phase Door"])
        brain.credit("Scroll of Phase Door", 1)
        brain.credit("Scroll of Phase Door", 1)
        brain.credit("Scroll of Phase Door", 1)
        self.assertEqual(brain.shopping_list(), [])


class PrayerBookTest(unittest.TestCase):
    """Books bind a caster (maintainer, 2026-10-25): a Priest learns and prays
    from the book that holds a prayer; without Words of Wisdom it learned
    nothing past level 5 (M5b round 18: 239 "No new spells to learn")."""

    @staticmethod
    def spell(stage: str, rows: dict[int, str]):
        o = command_obs(rows=rows)
        o.mode, o.stage = Mode.SPELL, stage
        return o

    @staticmethod
    def pack_list(rows: dict[int, str]):
        o = command_obs(rows={0: "Inventory", **rows})
        o.mode, o.stage = Mode.ITEM, "list"
        return o

    def priest(self):
        from moria_playtest import goals
        return Brain(goals.for_character(GOALS["clvl10"], "human-priest"))

    def test_buys_the_next_book_at_its_level(self) -> None:
        brain = self.priest()
        o = command_obs(pos=(5, 5), dlvl=0, clvl=4)
        self.assertIsNone(brain.book_wanted(o))
        o = command_obs(pos=(5, 5), dlvl=0, clvl=5)
        self.assertEqual(brain.book_wanted(o), "Words of Wisdom")
        brain.book_next = "Words of Wisdom"
        # The Temple's line as the C64 shows it (M5b round 22, seed 1003 replay).
        temple = GearTest().store(brain, 3, [("Potion of Cure Critical Wo", 103),
                                             ("Holy Book of Prayers Words", 309)], 400)
        brain.decide(temple, None)
        self.assertEqual(brain.store_letter, "b")
        brain.credit("Holy Book of Prayers Words", 1)
        self.assertIn("Words of Wisdom", brain.books_owned)
        self.assertIsNone(brain.magic.books)                             # learn the pack order again
        self.assertTrue(brain.magic.study_due)
        self.assertIsNone(brain.book_wanted(o))

    def test_saves_for_a_wanted_book(self) -> None:
        """M5b round 22: a level-5 Priest reached the Temple with 172 gold
        against Words of Wisdom's 309."""
        brain = self.priest()
        o = command_obs(pos=(5, 5), dlvl=0, clvl=5)
        self.assertGreaterEqual(brain.gear_reserve(o), 310)   # Words of Wisdom: VMS 100 gp since M5b round 46
        brain.book_next = "Words of Wisdom"
        self.assertEqual(brain.clw_reserve(), 2)
        brain.books_owned.add("Words of Wisdom")
        self.assertLess(brain.gear_reserve(o), 330)

    def test_a_book_with_nothing_learned_counts_as_read(self) -> None:
        """M5b round 23: the game will not list a book nothing was learned
        from ("You don't know that spell."); the bot asked 1,500 times."""
        brain = self.priest()
        magic = brain.magic
        magic.books, magic.listed_books = ["Beginners Handbook", "Words of Wisdom"], {"Beginners Handbook"}
        magic.read_list()
        self.assertEqual(brain.decide(PrayerBookTest.spell("book", {0: "Prayer book (a-b)?"}), None).key, ord("B"))
        magic.note("You don't know that spell.")
        self.assertTrue(magic.listed)
        magic.study_book = "Words of Wisdom"
        magic.note("You learn from the book!")
        self.assertFalse(magic.listed)                                   # something to read there now

    def test_a_prayer_in_no_offered_book_is_not_retried(self) -> None:
        """M5b round 23b: Portal known, no offered book held it, and the bot
        asked 2,500 times."""
        brain = self.priest()
        magic = brain.magic
        from moria_playtest.magic import Prayer
        magic.books = ["Beginners Handbook", "Beginners Handbook"]
        magic.known["Portal"] = Prayer("b", 4, 5, "Words of Wisdom")
        magic.pray("Portal", "boxed in")
        self.assertEqual(brain.decide(PrayerBookTest.spell("book", {0: "Prayer book (a-b)?"}), None).key, 0x1B)
        self.assertIn("Portal", magic.refused)
        self.assertIsNone(magic.books)                                   # list them again

    def test_a_picked_up_book_is_owned_and_studied(self) -> None:
        brain = self.priest()
        magic = brain.magic
        magic.books, magic.study_due = ["Beginners Handbook"], False
        magic.read_list()
        self.assertEqual(brain.decide(PrayerBookTest.spell("book", {0: "Prayer book (a-b)?"}), None).key, ord("?"))
        brain.decide(PrayerBookTest.pack_list({1: " a) Holy Book of Prayers Beginners", 2: " b) Holy Book of Prayers Words"}), None)
        self.assertEqual(magic.books, ["Beginners Handbook", "Words of Wisdom"])
        self.assertTrue(magic.study_due)
        self.assertIsNone(brain.book_wanted(command_obs(pos=(5, 5), dlvl=0, clvl=6)))

    def test_pack_list_names_cut_short(self) -> None:
        from moria_playtest.magic import book_of
        self.assertEqual(book_of("Holy Book of Prayers Words"), "Words of Wisdom")
        self.assertEqual(book_of("Holy Book of Prayers [Chants and Blessings]"), "Chants and Blessings")
        self.assertIsNone(book_of("Potion of Cure Light Wound"))

    def test_a_warrior_wants_no_book(self) -> None:
        brain = Brain(GOALS["clvl10"])
        self.assertIsNone(brain.book_wanted(command_obs(pos=(5, 5), dlvl=0, clvl=20)))

    def test_studies_the_latest_book_first_whatever_the_pack_order(self) -> None:
        # M5b round 35: with the Handbook first in the pack, every study went
        # to its leftovers and Cure Medium Wounds was never learned.
        brain = self.priest()
        magic = brain.magic
        magic.new_book()
        magic.study()
        self.assertEqual(brain.decide(self.spell("book", {0: "Study which book (a-b)?"}), None).key, ord("?"))
        listing = self.pack_list({1: " a) Beginners Handbook", 2: " b) Words of Wisdom"})
        self.assertEqual(brain.decide(listing, None).key, ord("B"))

    def test_studies_each_book_then_prays_from_the_right_one(self) -> None:
        brain = self.priest()
        magic = brain.magic
        magic.new_book()
        magic.study()
        self.assertEqual(brain.decide(self.spell("book", {0: "Study which book (a-b)?"}), None).key, ord("?"))
        listing = self.pack_list({1: " a) Words of Wisdom", 2: " b) Beginners Handbook"})
        self.assertEqual(brain.decide(listing, None).key, ord("A"))     # the first book not done
        self.assertEqual(magic.books, ["Words of Wisdom", "Beginners Handbook"])
        magic.note("No new spells to learn.")
        self.assertTrue(magic.study_due)                                 # the Handbook is left
        magic.study()
        self.assertEqual(brain.decide(self.spell("book", {0: "Study which book (a-b)?"}), None).key, ord("B"))
        magic.note("No new spells to learn.")
        self.assertFalse(magic.study_due)
        # Praying Cure Medium Wounds: its list is read in Words of Wisdom.
        magic.read_list()
        self.assertEqual(brain.decide(self.spell("book", {0: "Prayer book (a-b)?"}), None).key, ord("A"))
        brain.decide(self.spell("which", {0: "Pray which? (a-b, ESC)"}), None)
        brain.decide(self.spell("list", {0: "              Prayer Book", 2: " a) Portal                     4    5",
                                         3: " b) Cure Medium Wounds         4    5",
                                         24: "     Pray which? (a-b, esc)"}), None)
        self.assertEqual(magic.known["Cure Medium Wounds"].book, "Words of Wisdom")
        magic.pray("Cure Medium Wounds", "hurt")
        self.assertEqual(brain.decide(self.spell("book", {0: "Prayer book (a-b)?"}), None).key, ord("A"))
        self.assertEqual(brain.decide(self.spell("which", {0: "Pray which? (a-b, ESC)"}), None).key, ord("B"))


class CasterPrayerTest(unittest.TestCase):
    """A Priest's prayers past level 5 (maintainer, 2026-10-25): Orb of
    Draining, Blind Creature, Chant, Sanctuary and Portal."""

    @staticmethod
    def priest(known: dict, mp: int = 20):
        from moria_playtest import goals
        from moria_playtest.magic import Prayer
        brain = Brain(goals.for_character(GOALS["clvl10"], "human-priest"))
        brain.food, brain.magic.study_due, brain.magic.listed = 5, False, True
        brain.magic.known = {name: Prayer(*spec) for name, spec in known.items()}
        o = command_obs(pos=(5, 5), dlvl=4, clvl=9, hp=40, mhp=40,
                        rows={23: f"HP:40/40  MP:{mp}/20 AC:10 AU:32"})
        return brain, o

    def test_orb_at_a_creature_in_line_keeping_mana_for_a_heal(self) -> None:
        brain, o = self.priest({"Orb of Draining": ("b", 7, 9, "Chants and Blessings"),
                                "Cure Medium Wounds": ("c", 4, 5, "Words of Wisdom")})
        view = town_view((5, 5), (40, 40), dlvl=4)
        view.creatures = {(9, 5): Creature("k", 1)}                   # in line, four east
        decision = brain.invoke(o, view)
        self.assertEqual(decision.reason, "pray Orb of Draining at 'k'")
        self.assertEqual(brain.pending, DIRS[(1, 0)])
        _, low = self.priest({}, mp=10)                                 # 10 - 7 < 4: keep the heal
        brain.pending = None
        self.assertIsNone(brain.invoke(low, view))
        view.creatures = {(9, 6): Creature("k", 1)}                   # not in line
        self.assertIsNone(brain.invoke(o, view))

    def test_bless_find_traps_and_slow_poison(self) -> None:
        """M5f: Priests prayed only heals, Blind Creature, Chant and Orb;
        Bless, Find Traps and the poison prayers went unused while traps and
        poison killed them."""
        brain, o = self.priest({"Bless": ("c", 1, 1), "Find Traps": ("f", 2, 3), "Slow Poison": ("h", 2, 3)})
        view = town_view((5, 5), (40, 40), dlvl=2)
        view.creatures = {(7, 5): Creature("p", 2)}                   # a Novice Priest two squares off
        self.assertEqual(brain.invoke(o, view).reason, "a hard fight coming: pray Bless")
        brain.chant_until = 0
        hurt = command_obs(pos=(5, 5), dlvl=4, clvl=9, hp=3, mhp=40, rows={23: "HP:3/40  MP:20/20 AC:10 AU:32"})
        self.assertIsNone(brain.invoke(hurt, view))                    # not at 3 HP (M5 regression, seed 1016)
        brain.chant_until = 0
        brain.level.retreat_to = (40, 40)                              # running for the stairs
        self.assertIsNone(brain.invoke(o, view))                       # not mid-flight (2026-11-03 traces)
        quiet = town_view((5, 5), (40, 40), dlvl=2)
        self.assertEqual(brain.find_traps(o, quiet).reason, "pray Find Traps")
        brain.poisoned = True
        self.assertEqual(brain.pray(o, quiet).reason, "poisoned: pray Slow Poison")

    def test_walks_away_from_a_slow_snake_it_cannot_hurt(self) -> None:
        # M5f round 13, seed 1006: a Gnome Mage traded 40 blows with a Large
        # Brown Snake (AC 35, speed 0) and died with full mana; its 'R' at
        # level 1 is shared with the faster Large White Snake.
        from moria_playtest import knowledge
        self.assertIn("Large Brown Snake", knowledge.slow_names())
        self.assertNotIn("Large White Snake", knowledge.slow_names())
        brain = Brain(GOALS["clvl10"])
        brain.food = 3
        view = town_view((5, 5), (40, 40), dlvl=1)
        view.creatures = {(5, 6): Creature("R", 1)}
        o = command_obs(pos=(5, 5), dlvl=1, clvl=2, hp=16, mhp=16, rows={0: "You miss the Large Brown Snake."})
        brain.messages = o.rows[0]
        self.assertNotEqual(brain.fight(o, view).layer, "fight")               # walks away
        brain.messages = "You miss the Large White Snake."
        self.assertEqual(brain.fight(o, view).layer, "fight")                  # a White Snake keeps up

    def test_blind_creature_on_one_it_would_lose_to(self) -> None:
        brain, o = self.priest({"Blind Creature": ("a", 4, 5, "Words of Wisdom")})
        view = town_view((5, 5), (40, 40), dlvl=4)
        view.creatures = {(6, 5): Creature("n", 5)}                   # a naga, beside
        self.assertGreater(brain.fight_odds(Creature("n", 5), o), 0.6)
        self.assertEqual(brain.invoke(o, view).reason, "pray Blind Creature at 'n'")
        self.assertIsNone(brain.invoke(o, view))                       # not again at once
        view.creatures = {(6, 5): Creature("w", 1)}                   # an easy one
        brain.level.blind_until = 0
        self.assertIsNone(brain.invoke(o, view))

    def test_chant_before_a_hard_fight_once(self) -> None:
        brain, o = self.priest({"Chant": ("d", 5, 5, "Words of Wisdom"),
                                "Cure Medium Wounds": ("c", 4, 5, "Words of Wisdom")})
        view = town_view((5, 5), (40, 40), dlvl=4)
        view.creatures = {(7, 6): Creature("n", 5)}                   # a naga, not in line
        self.assertEqual(brain.invoke(o, view).reason, "a hard fight coming: pray Chant")
        self.assertIsNone(brain.invoke(o, view))                       # chanted
        brain.chant_until = 0
        view.creatures = {(7, 6): Creature("w", 1)}                   # an easy one: no Chant
        self.assertIsNone(brain.invoke(o, view))

    def test_sanctuary_then_portal_when_boxed_in(self) -> None:
        brain, o = self.priest({"Sanctuary": ("e", 5, 7, "Words of Wisdom"), "Portal": ("b", 4, 5, "Words of Wisdom")})
        hurt = command_obs(pos=(5, 5), dlvl=4, clvl=9, hp=15, mhp=40, rows={23: "HP:15/40  MP:20/20 AC:10 AU:32"})
        view = town_view((5, 5), (40, 40), dlvl=4)
        brain.adjacent = [Creature("k", 1), Creature("k", 1)]
        self.assertEqual(brain.phase_door(hurt, view).reason, "HP 15/40, 2 beside: pray Sanctuary")
        brain.adjacent = [Creature("w", 4)]                            # one breeder: no Sanctuary, no scroll
        self.assertEqual(brain.phase_door(hurt, view).reason, "HP 15/40, no way out: pray Portal")
        brain.phase = 1                                                # a scroll is certain: it first
        self.assertEqual(brain.phase_door(hurt, view).layer, "phase")
        brain.phase = 0
        brain, _ = self.priest({"Sanctuary": ("e", 5, 7, "Words of Wisdom")})   # no Portal known
        brain.adjacent = [Creature("w", 4)]
        self.assertIsNone(brain.phase_door(hurt, view))               # M5b round 24: no Portal loop


def goals_for(character: str):
    from moria_playtest import goals
    return goals.for_character(GOALS["clvl10"], character)


class MageBookTest(unittest.TestCase):
    """Mage-book casters (M5d): every Rogue and Ranger stalled at its first
    spell level on the Study list the bot did not know."""

    @staticmethod
    def caster(character: str, known: dict, mp: int = 6):
        from moria_playtest import goals
        from moria_playtest.magic import Prayer
        brain = Brain(goals.for_character(GOALS["clvl10"], character))
        brain.food, brain.magic.study_due, brain.magic.listed = 5, False, True
        brain.magic.known = {name: Prayer(*spec) for name, spec in known.items()}
        brain.magic.listed_books = {"Beginners-Magick"}
        o = command_obs(pos=(5, 5), dlvl=2, clvl=5, hp=30, mhp=30,
                        rows={23: f"HP:30/30  MP:{mp}/6 AC:10 AU:32"})
        return brain, o

    def test_surrounded_it_escapes_before_it_heals(self) -> None:
        # 2026-11-04: a level-21 Mage beside three creatures prayed Cure Light
        # Wounds five times to death with 25 mana and Phase Door known.
        brain, _ = self.caster("human-mage", {"Cure Light Wounds": ("d", 5, 4, "Beginners-Magick"),
                                              "Phase Door": ("c", 3, 2, "Beginners-Magick")}, mp=25)
        view = town_view((5, 5), (30, 30), dlvl=15)
        two = [Creature("k", 1), Creature("k", 1)]
        view.creatures = {(6, 5): two[0], (4, 5): two[1]}
        brain.adjacent = two
        hurt = command_obs(pos=(5, 5), dlvl=15, clvl=21, hp=35, mhp=110,
                           rows={0: "the Kobold hits you.", 23: "HP:35/110  MP:25/30 AC:10 AU:32"})
        self.assertIsNone(brain.pray(hurt, view))
        self.assertEqual(brain.phase_door(hurt, view).reason, "HP 35/110, no way out: cast Phase Door")
        brain.adjacent = two[:1]                                   # one beside, over a third: heal as before
        view.creatures = {(6, 5): two[0]}
        self.assertEqual(brain.pray(hurt, view).reason, "HP 35/110: pray Cure Light Wounds")

    def test_the_least_cast_spell_is_tried_first(self) -> None:
        # 2026-11-05: a level-25 Paladin tried Cure Light Wounds at full HP 308
        # times, its effect never shown, and never Earthquake.
        import dataclasses
        brain, _ = self.caster("human-paladin", {"Cure Light Wounds": ("b", 1, 1, "Beginners Handbook"),
                                                 "Earthquake": ("f", 15, 21, "Chants and Blessings")}, mp=40)
        brain.goal = dataclasses.replace(brain.goal, exercise=True)
        brain.magic.listed_books = {"Beginners Handbook", "Chants and Blessings"}
        view = town_view((5, 5), (30, 30), dlvl=15)
        o = command_obs(pos=(5, 5), dlvl=15, clvl=25, hp=150, mhp=150, rows={23: "HP:150/150  MP:40/40 AC:10 AU:32"})
        self.assertEqual(brain.exercise(o, view).reason, "try Cure Light Wounds: its effect not seen yet")
        brain.magic.ledger["Cure Light Wounds"] = {"cast": 3, "effect": 0, "failed": 0, "evidence": ""}
        brain.level.exercise_after = 0
        self.assertEqual(brain.exercise(o, view).reason, "try Earthquake: its effect not seen yet")

    def test_it_walks_out_of_a_molds_reach(self) -> None:
        # 2026-11-05: a level-26 Gnome Warrior, too afraid to strike, stood
        # beside a Green Mold and a Yellow Worm mass until the mold killed it.
        from moria_playtest import knowledge
        from moria_playtest.brain import Brain
        names = knowledge.kinds_by_name()
        mold = Creature(*names["Green Mold"])
        worm = Creature(*sorted(k for k in knowledge.slow_kinds() if k[0] not in knowledge.stationary_glyphs())[0])
        view = town_view((5, 5), (30, 30), dlvl=24)
        view.creatures = {(6, 5): mold, (5, 6): worm}                   # the mold east, the worm south
        decision = Brain.walk_away(view, set(view.creatures))
        self.assertEqual(decision.reason, "walk away from a slower creature")
        step = next(d for d, k in DIRS.items() if k == decision.key)
        to = (5 + step[0], 5 + step[1])
        self.assertGreater(max(abs(to[0] - 6), abs(to[1] - 5)), 1)       # out of the mold's reach
        self.assertGreaterEqual(max(abs(to[0] - 5), abs(to[1] - 6)), 1)  # no nearer the worm

    def test_out_of_mana_and_no_rest_it_leaves_the_level(self) -> None:
        # 2026-11-05: a level-20 Gnome Mage at 0-5 mana explored back into a
        # Guardian Naga three times, resting refused with it close.
        brain, _ = self.caster("gnome-mage", {"Magic Missile": ("a", 1, 1, "Beginners-Magick")}, mp=3)
        view = town_view((5, 5), (30, 30), dlvl=15)
        o = command_obs(pos=(5, 5), dlvl=15, clvl=20, hp=37, mhp=64, rows={23: "HP:37/64  MP:3/31 AC:10 AU:32"})
        brain.level.breeders_seen = {(8, 5): o.step}                    # something close, out of sight
        self.assertIsNone(brain.rest(o, view))
        self.assertTrue(brain.level.scum)
        brain.level.scum = False
        full = command_obs(pos=(5, 5), dlvl=15, clvl=20, hp=37, mhp=64, rows={23: "HP:37/64  MP:20/31 AC:10 AU:32"})
        self.assertIsNone(brain.rest(full, view))
        self.assertFalse(brain.level.scum)                              # mana enough: as before

    def test_caught_again_after_a_phase_it_teleports(self) -> None:
        # 2026-11-05: a level-21 Mage cast Phase Door 30 times in a Vorpal
        # Bunny swarm, each jump among more of them, Teleport Self known.
        brain, _ = self.caster("human-mage", {"Phase Door": ("c", 3, 2, "Beginners-Magick"),
                                              "Teleport Self": ("e", 7, 6, "Magick I")}, mp=25)
        brain.magic.listed_books = {"Beginners-Magick", "Magick I"}
        view = town_view((5, 5), (30, 30), dlvl=15)
        two = [Creature("k", 1), Creature("k", 1)]
        view.creatures, brain.adjacent = {(6, 5): two[0], (4, 5): two[1]}, two
        def hurt(step):
            o = command_obs(pos=(5, 5), dlvl=15, clvl=21, hp=35, mhp=110,
                            rows={0: "the Kobold hits you.", 23: "HP:35/110  MP:25/30 AC:10 AU:32"})
            o.step = step
            return o
        self.assertEqual(brain.phase_door(hurt(100), view).reason, "HP 35/110, no way out: cast Phase Door")
        self.assertEqual(brain.phase_door(hurt(110), view).reason, "HP 35/110, caught again: cast Teleport Self")
        self.assertEqual(brain.phase_door(hurt(200), view).reason, "HP 35/110, no way out: cast Phase Door")   # a new fight

    def test_heals_losing_to_unseen_attackers_give_way_to_the_escape(self) -> None:
        # 2026-11-05: a blinded level-24 Mage prayed Cure Light Wounds 13 times
        # among a Magic User's summons, nothing in view, HP 36-48 throughout.
        brain, _ = self.caster("human-mage", {"Cure Light Wounds": ("d", 5, 4, "Beginners-Magick"),
                                              "Phase Door": ("c", 3, 2, "Beginners-Magick")}, mp=25)
        view = town_view((5, 5), (30, 30), dlvl=15)
        brain.adjacent = []
        def hit(hp, step):
            o = command_obs(pos=(5, 5), dlvl=15, clvl=24, hp=hp, mhp=125,
                            rows={0: "the Huge White Bat hits you.", 23: f"HP:{hp}/125  MP:25/37 AC:10 AU:32"})
            o.step = step
            brain.attacked = True
            return o
        self.assertEqual(brain.pray(hit(44, 100), view).reason, "HP 44/125: pray Cure Light Wounds")
        self.assertEqual(brain.pray(hit(45, 105), view).reason, "HP 45/125: pray Cure Light Wounds")   # gained a point
        self.assertIsNone(brain.pray(hit(44, 110), view))                    # no better off: losing
        self.assertTrue(brain.phase_due(hit(44, 110)))
        self.assertEqual(brain.phase_door(hit(44, 110), view).reason, "HP 44/125, no way out: cast Phase Door")

    def test_a_heal_that_is_losing_gives_way_to_the_escape(self) -> None:
        # 2026-11-04: Mages prayed Cure Light Wounds eight times in a row
        # beside one Fire Spirit and died holding five potions.
        brain, _ = self.caster("human-mage", {"Cure Light Wounds": ("d", 5, 4, "Beginners-Magick"),
                                              "Phase Door": ("c", 3, 2, "Beginners-Magick")}, mp=25)
        view = town_view((5, 5), (30, 30), dlvl=15)
        one = Creature("k", 1)
        view.creatures, brain.adjacent = {(6, 5): one}, [one]
        def hurt(hp, step):
            o = command_obs(pos=(5, 5), dlvl=15, clvl=21, hp=hp, mhp=110,
                            rows={0: "the Kobold hits you.", 23: f"HP:{hp}/110  MP:25/30 AC:10 AU:32"})
            o.step = step
            return o
        self.assertEqual(brain.pray(hurt(50, 100), view).reason, "HP 50/110: pray Cure Light Wounds")
        self.assertIsNone(brain.pray(hurt(45, 104), view))                 # no better off: losing
        self.assertEqual(brain.phase_door(hurt(45, 104), view).reason, "HP 45/110, no way out: cast Phase Door")
        fresh, _ = self.caster("human-mage", {"Cure Light Wounds": ("d", 5, 4, "Beginners-Magick")}, mp=25)
        fresh.adjacent = [one]
        fresh.pray(hurt(50, 100), view)
        self.assertEqual(fresh.pray(hurt(52, 104), view).reason, "HP 52/110: pray Cure Light Wounds")   # gaining

    def test_a_breeder_is_not_the_target_while_something_else_threatens(self) -> None:
        # 2026-11-05: Lightning Bolts at a Red Worm mass while a Priest's
        # spells killed the Mage.
        from moria_playtest import knowledge
        brain, o = self.caster("human-ranger", {"Magic Missile": ("a", 1, 1, "Beginners-Magick")})
        # The toughest breeder, so it is worth a spell alone (a set's order varies by run).
        worm = Creature(*max(sorted(knowledge.breeder_kinds()), key=lambda k: knowledge.strength().get(k, (0.0, 0))[0]))
        view = town_view((5, 5), (30, 30), dlvl=2)
        view.creatures = {(7, 5): worm, (5, 9): Creature("k", 1)}       # the worm east, the Kobold south
        self.assertEqual(brain.invoke(o, view).reason, "cast Magic Missile at 'k'")
        view.creatures = {(7, 5): worm}
        self.assertEqual(brain.invoke(o, view).reason, f"cast Magic Missile at '{worm.glyph}'")   # alone: fair game
        # Half the mana stays for the escape: Mages met breeding swarms with 1
        # mana, spent bolt by bolt (2026-11-05).
        low = command_obs(pos=(5, 5), dlvl=2, clvl=5, hp=30, mhp=30, rows={23: "HP:30/30  MP:3/6 AC:10 AU:32"})
        self.assertIsNone(brain.invoke(low, view))
        view.creatures = {(7, 5): worm, (5, 9): Creature("k", 1)}
        self.assertEqual(brain.invoke(low, view).reason, "cast Magic Missile at 'k'")   # not a breeder: as before

    def test_an_unconfirmed_recharge_buys_something_to_recharge(self) -> None:
        # 2026-11-04: Recharge Item I cast 156,000 times with nothing to recharge.
        from moria_playtest.brain import MAGIC_SHOP, RECHARGEABLE
        brain, _ = self.caster("human-mage", {"Recharge Item I": ("e", 9, 7, "Conjurings-and-Tricks")})
        brain.book_next = None
        brain.at_store = MAGIC_SHOP
        brain.on_item_after["Recharge Item I"] = 10**9
        self.assertTrue(brain.recharge_wanted())
        self.assertEqual(brain.shopping_list()[:len(RECHARGEABLE)], list(RECHARGEABLE))
        brain.credit("Staff of Detect Monsters (5 charges)", 1)
        self.assertFalse(brain.recharge_wanted())
        self.assertNotIn("Recharge Item I", brain.on_item_after)          # tried again at once
        self.assertFalse(set(RECHARGEABLE) & set(brain.shopping_list()))

    def test_the_study_list_is_classified(self) -> None:
        from moria_playtest.game import classify
        o = command_obs(rows={0: "              Study", 1: "    Name              Mana Lvl",
                              2: " a) Detect Monsters            1    5", 24: "     Learn which? (a-a, esc)"})
        self.assertEqual(classify(o, ABI, 0), (Mode.SPELL, "learn"))   # 0: not the command prompt
        o = command_obs(rows={0: "              Mage Book", 2: " a) Magic Missile              1    3",
                              24: "     Cast which? (a-a, esc)"})
        self.assertEqual(classify(o, ABI, 0), (Mode.SPELL, "list"))

    def test_studies_and_learns_by_rank(self) -> None:
        brain, _ = self.caster("human-ranger", {})
        magic = brain.magic
        self.assertTrue(magic.mage)
        magic.new_book()
        self.assertEqual(magic.study()[0], ord("F"))
        self.assertEqual(brain.decide(PrayerBookTest.spell("book", {0: "Study which book (a-a)?"}), None).key, ord("A"))
        learn = PrayerBookTest.spell("learn", {0: "Study", 2: " a) Detect Monsters            2    3",
                                               3: " b) Magic Missile              1    3",
                                               4: " c) Phase Door                 2    3"})
        self.assertEqual(brain.decide(learn, None).key, ord("B"))      # the attack first
        magic.note("You learn from the book!")
        self.assertTrue(magic.study_due)                                 # perhaps another
        magic.study()
        brain.decide(PrayerBookTest.spell("book", {0: "Study which book (a-a)?"}), None)
        rogue = PrayerBookTest.spell("learn", {0: "Study", 2: " a) Detect Monsters            1    5"})
        self.assertEqual(brain.decide(rogue, None).key, ord("A"))      # nothing ranked: the first offered

    def test_casts_magic_missile_with_m(self) -> None:
        brain, o = self.caster("human-ranger", {"Magic Missile": ("a", 1, 3, "Beginners-Magick")})
        view = town_view((5, 5), (30, 30), dlvl=2)
        view.creatures = {(9, 5): Creature("k", 1)}                   # in line, four east
        decision = brain.invoke(o, view)
        self.assertEqual((decision.key, decision.reason), (ord("M"), "cast Magic Missile at 'k'"))
        self.assertEqual(brain.pending, DIRS[(1, 0)])
        self.assertEqual(brain.decide(PrayerBookTest.spell("book", {0: "Spell book (a-a)?"}), None).key, ord("A"))
        self.assertEqual(brain.decide(PrayerBookTest.spell("which", {0: "Cast which? (a-a, ESC)"}), None).key, ord("A"))
        hurt = command_obs(pos=(5, 5), dlvl=2, clvl=5, hp=9, mhp=30, rows={23: "HP:9/30  MP:6/6 AC:10 AU:32"})
        view.creatures = {(6, 5): Creature("k", 1)}                   # beside, hurt: escape first (round 4)
        brain.adjacent = [Creature("k", 1)]
        brain.phase = 1                                                # a Phase Door scroll held
        near_death = command_obs(pos=(5, 5), dlvl=2, clvl=5, hp=8, mhp=30, rows={23: "HP:8/30  MP:6/6 AC:10 AU:32"})
        self.assertIsNone(brain.invoke(near_death, view))                  # phase_door acts: escape first
        self.assertEqual(brain.choose(near_death, view).layer, "phase")
        self.assertEqual(brain.invoke(hurt, view).reason, "cast Magic Missile at 'k'")   # 9/30: phase_door would not act (M5f round 12)
        self.assertEqual(brain.cornered_cast(hurt, view).reason, "cast Magic Missile at 'k'")   # no escape taken: cast, not melee
        brain.phase = 0                                                # nothing to escape with (M5f)
        self.assertEqual(brain.invoke(hurt, view).reason, "cast Magic Missile at 'k'")
        brain.oil = 5
        self.assertEqual(brain.choose(hurt, view).reason, "cast Magic Missile at 'k'")         # not oil, not the dagger
        self.assertEqual(brain.invoke(o, view).reason, "cast Magic Missile at 'k'")   # not hurt: cast
        priest, _ = CasterPrayerTest.priest({"Magic Missile": ("a", 1, 3)})   # a Priest's list has none
        self.assertEqual(priest.magic.key, ord("P"))

    def test_the_full_repertoire(self) -> None:
        """M5f: Mages learned Stinking Cloud, Find Hidden Traps/Doors and the
        second book's spells' places but cast only Magic Missile and bought
        no second book (maintainer, 2026-10-27: "mages are only successful by
        using their full spell repertoire")."""
        from moria_playtest import magic as m
        known = {"Magic Missile": ("a", 1, 1, "Beginners-Magick"), "Find Hidden Traps/Doors": ("f", 3, 3, "Beginners-Magick"),
                 "Lightning Bolt": ("b", 4, 5, "Magick I"), "Cure Poison": ("d", 5, 5, "Magick I"),
                 "Teleport Self": ("e", 6, 7, "Magick I")}
        brain, o = self.caster("elf-mage", known, mp=20)
        o.rows[23] = "HP:30/30  MP:20/20 AC:10 AU:32"
        o = command_obs(pos=(5, 5), dlvl=2, clvl=7, hp=30, mhp=30, rows={23: "HP:30/30  MP:20/20 AC:10 AU:32"})
        self.assertEqual(brain.mage_attack(o, Creature("r", 1)), "Magic Missile")     # 2 HP: one of either, the cheaper
        self.assertEqual(brain.mage_attack(o, Creature("k", 1)), "Lightning Bolt")    # 12 HP: one bolt, not two missiles
        brain.magic.known.pop("Lightning Bolt")
        self.assertEqual(brain.mage_attack(o, Creature("k", 1)), "Magic Missile")     # the bolt not learned yet
        brain.magic.known["Fire Bolt"] = m.Prayer("c", 9, 7, "Magick II")             # 6d8 (level 15, here 7 to test)
        self.assertEqual(brain.mage_attack(o, Creature("p", 2)), "Fire Bolt")         # 22.5 HP: one Fire Bolt
        view = town_view((5, 5), (30, 30), dlvl=2)
        self.assertEqual(brain.find_traps(o, view).reason, "pray Find Hidden Traps/Doors")
        later = command_obs(pos=(5, 5), dlvl=2, clvl=7, hp=30, mhp=30, rows={23: "HP:30/30  MP:20/20 AC:10 AU:32"})
        later.step = 10
        self.assertIsNone(brain.find_traps(later, view))                             # not again for FIND_TRAPS_EVERY
        view.creatures = {(9, 5): Creature("k", 1)}
        later.step = 100
        self.assertIsNone(brain.find_traps(later, view))                             # not with a creature in view
        cured = brain.decide(command_obs(pos=(5, 5), dlvl=2, clvl=7, hp=30, mhp=30,
                                         rows={0: "You feel poisoned.", 23: "HP:30/30  MP:20/20 AC:10 AU:32"}),
                             town_view((5, 5), (30, 30), dlvl=2))
        self.assertEqual(cured.reason, "poisoned: pray Cure Poison")
        self.assertFalse(brain.poisoned)            # cast: cured until HP falls again (2026-11-04: 14,728 casts)
        self.assertTrue(brain.can_phase(o))                                          # Teleport Self is a way out
        # Books: a level-3 Mage wants Magick I from the Magic Shop.
        self.assertEqual(m.book_of("Spellbook Magick II"), "Magick II")
        self.assertEqual(m.book_of("Spellbook Magick I"), "Magick I")
        fresh = Brain(goals_for("elf-mage"))
        self.assertIn("Beginners-Magick", fresh.books_owned)
        self.assertEqual(fresh.book_wanted(command_obs(clvl=3)), "Magick I")
        self.assertIsNone(fresh.book_wanted(command_obs(clvl=2)))
        fresh.book_next, fresh.at_store = "Magick I", 5
        self.assertEqual(fresh.shopping_list()[0], "Spellbook Magick I")   # the book first (wands after, 2026-11-04)
        fresh.credit("Spellbook Magick I", 1)
        self.assertIn("Magick I", fresh.books_owned)

    def test_a_bolt_that_reached_nothing_unmarks_the_creature(self) -> None:
        # M5f round 9: a '$' identified as Creeping Coins stayed one after
        # they had gone, and Mages cast 14,805 Magic Missiles at floor gold.
        brain, o = self.caster("elf-mage", {"Magic Missile": ("a", 1, 1, "Beginners-Magick")})
        brain.decide(o, town_view((5, 5), (30, 30), dlvl=2))          # arrive on the level
        view = town_view((5, 5), (30, 30), dlvl=2)
        view.unknown = {(9, 5): "$"}
        brain.level.identified[((9, 5), "$")] = ("creature", "Creeping Copper Coins")
        o.step = 1
        brain.decide(o, view)                                          # identify: '$' counts as coins
        self.assertEqual(brain.aimed, ((9, 5), "$"))
        self.assertEqual(brain.decide(PrayerBookTest.spell("book", {0: "Spell book (a-a)?"}), None).key, ord("A"))
        after = command_obs(pos=(5, 5), dlvl=2, clvl=5, hp=30, mhp=30, rows={23: "HP:30/30  MP:5/6 AC:10 AU:32"})
        after.step = 2
        view = town_view((5, 5), (30, 30), dlvl=2)
        view.unknown = {(9, 5): "$"}
        decision = brain.decide(after, view)                          # no hit, no message: nothing there
        self.assertEqual(brain.level.identified[((9, 5), "$")][0], "item")
        self.assertNotIn("Magic Missile", decision.reason)
        hit = Brain(GOALS["clvl10"])
        hit.aimed = ((9, 5), "k")
        hit.decide(command_obs(pos=(5, 5), dlvl=2, rows={0: "Your spell hits the Kobold."}), town_view((5, 5), (30, 30), dlvl=2))
        self.assertNotIn(((9, 5), "k"), hit.level.identified)          # it hit something: left alone

    def test_no_missile_at_a_creature_in_a_secret_door(self) -> None:
        # M5f round 10, seed 1012: a Kobold stood in a secret door (drawn in
        # the wall) beside an Elf Mage, which cast 14 Magic Missiles that hit
        # nothing; VMS fire_bolt strikes only on fopen squares. Melee reaches it.
        brain, o = self.caster("elf-mage", {"Magic Missile": ("a", 1, 1, "Beginners-Magick")})
        view = town_view((5, 5), (30, 30), dlvl=2, walls=[(x, 6) for x in range(2, 9)])
        view.creatures = {(5, 6): Creature("k", 1)}
        brain.adjacent = [view.creatures[(5, 6)]]
        brain.oil = 5
        self.assertIsNone(brain.invoke(o, view))
        self.assertIsNone(brain.throw(o, view))
        self.assertEqual(brain.choose(o, view).layer, "fight")
        view = town_view((5, 5), (30, 30), dlvl=2)                      # the same Kobold on the floor
        view.creatures = {(5, 6): Creature("k", 1)}
        self.assertEqual(brain.invoke(o, view).reason, "cast Magic Missile at 'k'")

    def test_out_of_mana_it_rests_even_after_a_close_call(self) -> None:
        # 2026-11-05: a level-24 Gnome Mage with no mana phased and explored
        # back into a Giant Ebony Ant.
        brain, _ = self.caster("gnome-mage", {"Magic Missile": ("a", 1, 1, "Beginners-Magick")})
        view = town_view((5, 5), (30, 30), dlvl=19)
        spent = command_obs(pos=(5, 5), dlvl=19, clvl=24, hp=35, mhp=76, rows={23: "HP:35/76  MP:1/30 AC:10 AU:32"})
        brain.track(spent, view)
        brain.level.near_until = spent.step + 20                            # something was close a moment ago
        self.assertEqual(brain.rest(spent, view).reason, "HP 35/76 MP 1/30: out of mana, rest")

    def test_rests_for_mana_at_full_hp(self) -> None:
        # M5f round 2: level-1 Halfling Mages walked on with no Magic
        # Missile left into the next Kobold.
        brain, _ = self.caster("halfling-mage", {"Magic Missile": ("a", 1, 1, "Beginners-Magick")})
        view = town_view((5, 5), (30, 30), dlvl=1)
        spent = command_obs(pos=(5, 5), dlvl=1, clvl=1, hp=6, mhp=6, rows={23: "HP:6/6  MP:0/2 AC:10 AU:32"})
        self.assertEqual(brain.rest(spent, view).reason, "HP 6/6 MP 0/2 and nothing in view")
        full = command_obs(pos=(5, 5), dlvl=1, clvl=1, hp=6, mhp=6, rows={23: "HP:6/6  MP:2/2 AC:10 AU:32"})
        self.assertIsNone(brain.rest(full, view))
        view.creatures = {(9, 5): Creature("k", 1)}
        self.assertIsNone(brain.rest(spent, view))                     # not with a creature in view

    def test_phase_door_spell_after_the_scroll(self) -> None:
        brain, _ = self.caster("human-rogue", {"Phase Door": ("b", 2, 7, "Beginners-Magick")})
        hurt = command_obs(pos=(5, 5), dlvl=2, clvl=7, hp=8, mhp=30, rows={23: "HP:8/30  MP:6/6 AC:10 AU:32"})
        view = town_view((5, 5), (30, 30), dlvl=2)
        brain.adjacent = [Creature("k", 1), Creature("k", 1)]
        brain.phase = 1
        self.assertEqual(brain.phase_door(hurt, view).layer, "phase")   # the scroll cannot fail
        brain.phase = 0
        self.assertEqual(brain.phase_door(hurt, view).reason, "HP 8/30, no way out: cast Phase Door")

    def test_keeps_its_spellbook_when_dropping_junk(self) -> None:
        """M5d round 1: a full pack dropped "Spellbook Beginners-Magick"."""
        brain, _ = self.caster("human-ranger", {})
        brain.dropping = True
        o = command_obs(rows={0: "Inventory", 1: "---------", 2: "a) Spellbook Beginners-Magick",
                              3: "b) 3 Wooden Torch (134 turns)", 4: "c) Dagger (1d4)"})
        o.mode, o.stage = Mode.ITEM, "list"
        self.assertEqual(brain.decide(o, None).reason, "drop Dagger (1d4)")

    def test_a_full_pack_drops_wands_and_staffs_it_does_not_use(self) -> None:
        # 2026-11-05: every "Wand of" kept filled a Mage's pack until the
        # General Store refused its food and light.
        brain, _ = self.caster("human-warrior", {})
        brain.dropping = True
        rows = {0: "Inventory", 1: "---------", 2: "a) Wand of Frost (5 charges)", 3: "b) Staff of Teleportation (4 charges)",
                4: "c) a Blue Potion", 5: "d) Wand of Light (3 charges)", 6: "e) an Iron Wand"}
        o = command_obs(rows=rows)
        o.mode, o.stage = Mode.ITEM, "list"
        self.assertEqual(brain.decide(o, None).reason, "drop Wand of Light (3 charges)")
        brain.dropping = True
        o = command_obs(rows={k: v for k, v in rows.items() if k != 5})
        o.mode, o.stage = Mode.ITEM, "list"
        self.assertEqual(brain.decide(o, None).reason, "drop an Iron Wand")    # no way to identify it
        brain.dropping = True
        o = command_obs(rows={0: "Inventory", 1: "---------", 2: "a) Wand of Frost (5 charges)",
                              3: "b) Wand of Frost (0 charges)"})
        o.mode, o.stage = Mode.ITEM, "list"
        self.assertEqual(brain.decide(o, None).reason, "drop Wand of Frost (0 charges)")   # spent, as a torch
        brain.dropping = True
        o = command_obs(rows={0: "Inventory", 1: "---------", 2: "a) Wand of Lightning (3 charges)",
                              3: "b) Wand of Lightning (6 charges)", 4: "c) Wand of Frost (5 charges)"})
        o.mode, o.stage = Mode.ITEM, "list"
        self.assertEqual(brain.decide(o, None).reason, "drop Wand of Lightning (3 charges)")   # one of each, the fuller
        # 2026-11-05: six wand kinds and five part-burnt torches filled packs.
        brain.dropping, brain.lamp = True, False
        o = command_obs(rows={0: "Inventory", 1: "---------", 2: "a) Wand of Fire Balls (5 charges)",
                              3: "b) Wand of Cold Balls (5 charges)", 4: "c) Wand of Frost (5 charges)",
                              5: "d) Wand of Stinking Cloud (5 charges)", 6: "e) Wooden Torch (134 turns)"})
        o.mode, o.stage = Mode.ITEM, "list"
        self.assertEqual(brain.decide(o, None).reason, "drop Wand of Stinking Cloud (5 charges)")   # the three strongest stay
        brain.dropping = True
        o = command_obs(rows={0: "Inventory", 1: "---------", 2: "a) Wooden Torch (23 turns)", 3: "b) Wooden Torch (134 turns)",
                              4: "c) Wooden Torch (111 turns)", 5: "d) Wooden Torch (124 turns)"})
        o.mode, o.stage = Mode.ITEM, "list"
        self.assertEqual(brain.decide(o, None).reason, "drop Wooden Torch (23 turns)")   # the three fullest stay
        # The game pads rows with spaces: a wand shown without charges kept
        # them in its name, and neither rule matched it (2026-11-05).
        brain.dropping = True
        o = command_obs(rows={0: "Inventory", 1: "---------", 2: "a) Wand of Fire Balls (magik)".ljust(60),
                              3: "b) Wand of Fire Balls".ljust(60)})
        o.mode, o.stage = Mode.ITEM, "list"
        self.assertEqual(brain.decide(o, None).reason, "drop Wand of Fire Balls")

    def test_with_nothing_else_to_spare_an_unknown_flavour_is_dropped(self) -> None:
        # 2026-11-05: a full pack refused every purchase for 150,000 steps.
        brain, _ = self.caster("human-mage", {})
        brain.dropping = True
        o = command_obs(rows={0: "Inventory", 1: "---------", 2: "a) Wand of Frost (5 charges)",
                              3: "b) Spellbook Beginners-Magick", 4: "c) a Blue Potion"})
        o.mode, o.stage = Mode.ITEM, "list"
        self.assertEqual(brain.decide(o, None).reason, "drop a Blue Potion: nothing else to spare")

    def test_a_cast_whose_book_is_gone_is_not_retried(self) -> None:
        # 2026-11-05: Stinking Cloud cast 48,050 times without Magick I.
        brain, o = self.caster("human-mage", {"Stinking Cloud": ("c", 3, 3, "Magick I")})
        brain.books_owned.add("Magick I")
        magic = brain.magic
        magic.pray("Stinking Cloud", "at a naga")
        magic.note("Cast which? (a-e, ESC) Never mind.")
        self.assertFalse(magic.can(o, "Stinking Cloud"))
        self.assertEqual(magic.lost_book, "Magick I")
        magic.note("Welcome to level 13.")
        self.assertTrue(magic.can(o, "Stinking Cloud"))

    def test_no_book_carried_is_not_retried(self) -> None:
        """M5d round 1: with no book, "You have nothing there." took no turn
        and the cast was asked again 56,018 times."""
        brain, o = self.caster("human-ranger", {"Magic Missile": ("a", 1, 3, "Beginners-Magick")})
        magic = brain.magic
        magic.pray("Magic Missile", "at a kobold")
        magic.note("You have nothing there.")
        self.assertFalse(magic.can(o, "Magic Missile"))
        magic.study()
        magic.note("You have nothing there.")
        self.assertFalse(magic.study_due)
        magic.note("Welcome to level 6.")
        self.assertTrue(magic.can(o, "Magic Missile"))                 # tried again a level on

    def test_mage_cure_light_wounds_heals_4d4(self) -> None:
        brain, _ = self.caster("human-ranger", {"Cure Light Wounds": ("c", 3, 5, "Beginners-Magick")})
        hurt = command_obs(pos=(5, 5), dlvl=2, clvl=5, hp=8, mhp=30, rows={23: "HP:8/30  MP:6/6 AC:10 AU:32"})
        view = town_view((5, 5), (30, 30), dlvl=2)
        brain.adjacent = [Creature("k", 1)]                             # a Kobold hits for ~4, under 4d4's 10
        decision = brain.pray(hurt, view)
        self.assertEqual((decision.key, decision.reason), (ord("M"), "HP 8/30: pray Cure Light Wounds"))


class MissileTest(unittest.TestCase):
    """A Rogue's or Ranger's launcher (M5d): buy one and its ammunition,
    wield it as a creature approaches in line, fire, then wield the melee
    weapon again beside a creature."""

    @staticmethod
    def ranger(launcher: str | None = "Short Bow", ammo: int = 10):
        from moria_playtest import goals
        brain = Brain(goals.for_character(GOALS["clvl10"], "human-ranger"))
        brain.food, brain.magic.study_due, brain.magic.listed = 5, False, True
        brain.launcher, brain.ammo = launcher, ammo
        o = command_obs(pos=(5, 5), dlvl=2, clvl=5, hp=30, mhp=30, rows={23: "HP:30/30  MP:0/0 AC:10 AU:32"})
        return brain, o

    def test_wields_the_launcher_fires_then_wields_the_weapon(self) -> None:
        brain, o = self.ranger()
        view = town_view((5, 5), (30, 30), dlvl=2)
        view.creatures = {(9, 5): Creature("k", 1)}                   # in line, four east
        d = brain.shoot(o, view)
        self.assertEqual((d.key, d.reason), (KEY_WEAR, "'k' approaching: wield the Short Bow"))
        self.assertEqual(brain.picking, "Short Bow")
        brain.picking = None
        d = brain.shoot(o, view)
        self.assertEqual((d.key, d.reason), (0xC6, "fire the Short Bow at 'k'"))
        self.assertEqual((brain.pending, brain.ammo), (DIRS[(1, 0)], 9))
        brain.pending = None
        brain.adjacent = [Creature("k", 1)]
        d = brain.shoot(o, view)
        self.assertEqual((d.key, brain.picking, brain.wielding_launcher), (KEY_WEAR, "Dagger", False))

    def test_holds_fire_out_of_line_too_close_or_without_ammunition(self) -> None:
        brain, o = self.ranger()
        view = town_view((5, 5), (30, 30), dlvl=2)
        view.creatures = {(9, 6): Creature("k", 1)}                   # not in line
        self.assertIsNone(brain.shoot(o, view))
        view.creatures = {(7, 5): Creature("k", 1)}                   # two off: no turn to change
        self.assertIsNone(brain.shoot(o, view))
        brain.ammo = 0
        view.creatures = {(9, 5): Creature("k", 1)}
        self.assertIsNone(brain.shoot(o, view))
        brain.track_missiles("No ammo.")
        warrior = Brain(GOALS["clvl10"])
        self.assertIsNone(warrior.shoot(o, view))                       # no launcher

    def test_buys_the_best_launcher_then_its_ammunition(self) -> None:
        brain, _ = self.ranger(launcher=None, ammo=0)
        stock = [("Sling", 5), ("Short Bow", 50), ("Light Crossbow", 140), ("Arrow", 1)]
        o = GearTest().store(brain, 2, stock, 100)                      # the Crossbow is over 100 - 20
        self.assertEqual(brain.missile_pick(o), ("b", "Short Bow"))
        brain.credit("Short Bow", 1)
        self.assertEqual((brain.launcher, brain.ammo), ("Short Bow", 0))
        self.assertEqual(brain.missile_pick(o), ("d", "Arrow"))         # the Crossbow is over the gear reserve
        brain.credit("Arrow", 1)
        self.assertEqual(brain.ammo, 1)
        self.assertIn("Arrow", brain.shopping_list())                   # the General Store too
        warrior = Brain(GOALS["clvl10"])
        self.assertIsNone(warrior.missile_pick(GearTest().store(warrior, 2, stock, 500)))

    def test_a_junk_drop_is_an_expected_prompt(self) -> None:
        brain, _ = self.ranger()
        self.assertFalse(brain.expects_item_prompt())
        brain.dropping = True
        self.assertTrue(brain.expects_item_prompt())

    def test_keeps_the_launcher_and_ammunition_when_dropping_junk(self) -> None:
        brain, _ = self.ranger()
        brain.dropping = True
        rows = {0: "Inventory", 2: "a) Short Bow", 3: "b) 12 Arrow", 4: "c) Bolt", 5: "d) Iron Shot"}
        o = command_obs(rows=rows)
        o.mode, o.stage = Mode.ITEM, "list"
        self.assertEqual(brain.decide(o, None).reason, "drop Bolt")   # a crossbow's: no use with a bow
        del rows[4]
        o = command_obs(rows=rows)
        o.mode, o.stage = Mode.ITEM, "list"
        brain.dropping, brain.listed = True, True
        self.assertEqual(brain.decide(o, None).reason, "drop Iron Shot")
        del rows[5]
        o = command_obs(rows=rows)
        o.mode, o.stage = Mode.ITEM, "list"
        brain.dropping, brain.listed = True, True
        self.assertTrue(brain.decide(o, None).reason.startswith("nothing to drop: cancel"))   # the bow and its arrows stay


class StartingKitTest(unittest.TestCase):
    """The 2026-10-25 kit fix: 5 rations and 5 torches, as VMS player_init and
    Umoria class_base_provisions give every class."""

    def test_counts_the_kit(self) -> None:
        brain = Brain(GOALS["clvl10"])
        self.assertEqual((brain.food, brain.torches), (5, 4))

    def test_a_priest_goes_to_the_armoury_first(self) -> None:
        from moria_playtest import goals
        view = town_view((5, 5), (40, 40), dlvl=0)
        view.stores = [(2, 2), (8, 5), (4, 2), (5, 2), (6, 2), (7, 2), (5, 9)]   # Armoury east
        priest = Brain(goals.for_character(GOALS["clvl10"], "human-priest"))
        o = command_obs(pos=(5, 5), dlvl=0, clvl=1)
        priest.track(o, view)
        self.assertEqual((priest.decide(o, view).reason, priest.at_store),
                         ("walk to the Armoury for better armour (a Priest's first stop)", 1))
        warrior = Brain(GOALS["clvl10"])
        warrior.track(o, view)
        self.assertNotEqual(warrior.decide(o, view).reason,
                            "walk to the Armoury for better armour (a Priest's first stop)")

    def test_the_dagger_sends_a_priest_to_the_weaponsmith_before_the_general_store(self) -> None:
        """M5b round 39: the General Store spent the weapon's price."""
        from moria_playtest import goals
        view = town_view((5, 5), (40, 40), dlvl=0)
        view.stores = [(2, 2), (8, 5), (4, 9), (5, 2), (6, 2), (7, 2), (5, 9)]
        priest = Brain(goals.for_character(GOALS["clvl10"], "human-priest"))
        o = command_obs(pos=(5, 5), dlvl=0, clvl=1)
        priest.track(o, view)
        priest.armoury_done = True                           # the Armoury came first
        priest.decide(o, view)
        self.assertEqual(priest.at_store, 2)                 # the Weaponsmith, not the General Store


class SearchModeTest(unittest.TestCase):
    """Search mode while moving about with nothing in view (maintainer,
    2026-10-25): every step searches for traps."""

    def test_turns_search_mode_on_with_nothing_in_view(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        view = town_view((5, 5), (40, 40), dlvl=1)
        off = command_obs(pos=(5, 5), dlvl=1, clvl=2, rows={21: "bot Half-Troll              LV:2  DL:1"})
        off.step = 100
        decision = brain.decide(off, view)
        self.assertEqual((decision.layer, decision.key), ("search-mode", ord("#")))
        off.step = 101
        self.assertNotEqual(brain.decide(off, view).layer, "search-mode")      # not again at once
        on = command_obs(pos=(5, 5), dlvl=1, clvl=2)                        # "Search*" shown
        on.step = 200
        self.assertNotEqual(brain.decide(on, view).layer, "search-mode")

    def test_not_turned_on_where_breathers_live(self) -> None:
        """2026-11-08: search mode is two turns a step, and a Mature Red Dragon
        in the dark breathed twice in one, 320 at 288/288 (C64 Balrog)."""
        from moria_playtest.brain import SCOUT_FROM
        brain = Brain(GOALS["deep"])
        view = town_view((5, 5), (40, 40), dlvl=SCOUT_FROM)
        off = command_obs(pos=(5, 5), dlvl=SCOUT_FROM, clvl=37, hp=288, mhp=288,
                          rows={21: f"bot Half-Troll              LV:37 DL:{SCOUT_FROM}"})
        self.assertIsNone(brain.search_mode(off, view))
        shallower = command_obs(pos=(5, 5), dlvl=SCOUT_FROM - 1, clvl=37, hp=288, mhp=288,
                                rows={21: f"bot Half-Troll              LV:37 DL:{SCOUT_FROM - 1}"})
        self.assertIsNotNone(brain.search_mode(shallower, town_view((5, 5), (40, 40), dlvl=SCOUT_FROM - 1)))

    def test_not_on_the_way_home_for_food(self) -> None:
        """M6: two turns of food a step, and Warriors on the 80-column ports'
        big maps starved walking home searching."""
        brain = Brain(GOALS["reach_dl2"])
        view = town_view((5, 5), (40, 40), dlvl=1)
        brain.track(command_obs(pos=(5, 5), dlvl=1, clvl=2), view)
        off = command_obs(pos=(5, 5), dlvl=1, clvl=2, rows={21: "bot Half-Troll              LV:2  DL:1"})
        off.step = 100
        self.assertIsNotNone(brain.search_mode(off, view))
        brain.search_mode_after = 0
        brain.food = 0
        self.assertIsNone(brain.search_mode(off, view))

    def test_turns_it_off_when_hurt_or_attacked(self) -> None:
        """M6: a spell does not end search mode (VMS), and a C128 Warrior fled
        a Novice Priest at half speed; Mages rested from poison searching."""
        brain = Brain(GOALS["reach_dl2"])
        view = town_view((5, 5), (40, 40), dlvl=1)
        on = {21: "bot Half-Troll  Search*     LV:2  DL:1"}
        off = {21: "bot Half-Troll              LV:2  DL:1"}
        decision = brain.search_mode(command_obs(pos=(5, 5), dlvl=1, clvl=2, hp=10, rows=on), view)
        self.assertEqual((decision.key, decision.reason), (ord("#"), "hurt: search mode off"))
        brain.unseen_attack = True
        decision = brain.search_mode(command_obs(pos=(5, 5), dlvl=1, clvl=2, rows=on), view)
        self.assertEqual((decision.key, decision.reason), (ord("#"), "under attack: search mode off"))
        # and not back on while hurt: no toggling every step
        brain.unseen_attack = False
        hurt = command_obs(pos=(5, 5), dlvl=1, clvl=2, hp=10, rows=off)
        hurt.step = 100
        self.assertIsNone(brain.search_mode(hurt, view))
        self.assertIsNone(brain.search_mode(command_obs(pos=(5, 5), dlvl=1, clvl=2, rows=on), view))   # well: left on

    def test_not_with_a_creature_in_view_or_in_town(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        off = {21: "bot Half-Troll              LV:2  DL:1"}
        busy = town_view((5, 5), (40, 40), dlvl=1, monsters={(9, 5)})
        self.assertNotEqual(brain.decide(command_obs(pos=(5, 5), dlvl=1, clvl=2, rows=off), busy).layer, "search-mode")
        town = town_view((5, 5), (40, 40), dlvl=0)
        self.assertNotEqual(brain.decide(command_obs(pos=(5, 5), dlvl=0, clvl=2, rows=off), town).layer, "search-mode")


class PhaseDoorTest(unittest.TestCase):
    """M5b round 11: a Paladin stood 250 steps on one square killing Blue
    Worm masses as fast as they bred, every step out into contact."""

    def test_reads_phase_door_when_boxed_in_and_hurt(self) -> None:
        brain = Brain(GOALS["reach_dl8"])
        brain.phase = 1
        view = town_view((5, 5), (40, 40), dlvl=4)
        hurt = command_obs(pos=(5, 5), dlvl=4, clvl=10, hp=30, mhp=64)
        brain.adjacent = [Creature("w", 4)]                            # a breeder
        decision = brain.phase_door(hurt, view)
        self.assertEqual((decision.layer, decision.key), ("phase", ord("R")))
        self.assertEqual(brain.picking, "Scroll of Phase Door")
        brain.adjacent = [Creature("k", 1)]                            # one, not breeding, not near death
        self.assertIsNone(brain.phase_door(hurt, view))
        brain.adjacent = [Creature("k", 1), Creature("k", 1)]         # two
        self.assertIsNotNone(brain.phase_door(hurt, view))
        well = command_obs(pos=(5, 5), dlvl=4, clvl=10, hp=60, mhp=64)
        self.assertIsNone(brain.phase_door(well, view))                # not hurt enough
        brain.phase = 0
        self.assertIsNone(brain.phase_door(hurt, view))                # none carried

    def test_picks_the_scroll_and_counts_it(self) -> None:
        brain = Brain(GOALS["reach_dl8"])
        brain.phase, brain.picking, brain.listed = 2, "Scroll of Phase Door", True
        o = command_obs(rows={0: "Read which scroll? (a-b)", 2: " a) Scroll of Word of Recall",
                              3: " b) Scroll of Phase Door"})
        self.assertEqual(brain.pick_item(o).key, ord("B"))
        self.assertEqual(brain.phase, 1)


class RetreatCommitTest(unittest.TestCase):
    """M3 round 16: a retreat keeps its staircase; flipping between two let
    followers catch the player at every turn-around."""

    def test_keeps_the_first_staircase(self) -> None:
        brain = Brain(GOALS["clvl5"])
        brain.food = 3
        view = town_view((10, 5), (4, 5), dlvl=3, monsters={(12, 5)}, stairs_type=0xA)
        view.types = [WALL] * (COLS * ROWS)                   # a corridor, stairs at both ends
        for x in range(4, 21):
            view.types[5 * COLS + x] = 0x0
        view.types[5 * COLS + 4] = view.types[5 * COLS + 20] = 0xA
        o = command_obs(pos=(10, 5), dlvl=3, clvl=3, hp=10, mhp=40)
        self.assertEqual(brain.decide(o, view).key, DIRS[(-1, 0)])   # west: the nearer one
        view.pos, view.creatures = (9, 5), {(7, 5): Creature("k", 1)}   # now one blocks the west
        decision = brain.decide(command_obs(pos=(9, 5), dlvl=3, clvl=3, hp=10, mhp=40), view)
        self.assertNotEqual((decision.layer, decision.key), ("retreat", DIRS[(1, 0)]))


    def ring(self, pos, monsters):
        """Corridors on rows 5 and 7 joined at x=4 and x=14; up stairs at (8, 7),
        within RETREAT_RANGE either way round (round 28)."""
        view = town_view(pos, (8, 7), dlvl=3, monsters=monsters, stairs_type=0xA)
        view.types = [WALL] * (COLS * ROWS)
        for x in range(4, 15):
            view.types[5 * COLS + x] = view.types[7 * COLS + x] = 0x0
        view.types[6 * COLS + 4] = view.types[6 * COLS + 14] = 0x0
        view.types[7 * COLS + 8] = 0xA
        return view

    def test_a_retreat_that_doubles_back_is_over(self) -> None:
        brain = Brain(GOALS["clvl5"])
        brain.food = 3
        hurt = dict(dlvl=3, clvl=3, hp=10, mhp=40)
        decision = brain.decide(command_obs(pos=(10, 5), **hurt), self.ring((10, 5), {(12, 5)}))
        self.assertEqual((decision.layer, decision.key), ("retreat", DIRS[(-1, 0)]))   # west way round
        decision = brain.decide(command_obs(pos=(9, 5), **hurt), self.ring((9, 5), {(6, 5)}))
        self.assertNotEqual((decision.layer, decision.key), ("retreat", DIRS[(1, 0)]))  # not back east


class BumpTest(unittest.TestCase):
    """M3 round 17: a move that leaves the player in place found something
    unseen on that tile (an invisible creature): stop walking into it."""

    def test_a_blocked_move_is_not_repeated(self) -> None:
        brain = Brain(GOALS["reach_dl5"])
        brain.food = 0                                       # resupply: head for the up stairs
        view = town_view((5, 5), (9, 5), dlvl=2, stairs_type=0xA)
        first = brain.decide(command_obs(pos=(5, 5), dlvl=2, clvl=3), view)
        self.assertEqual(first.key, DIRS[(1, 0)])
        view = town_view((5, 5), (9, 5), dlvl=2, stairs_type=0xA)
        again = brain.decide(command_obs(pos=(5, 5), dlvl=2, clvl=3, rows={0: "You are too afraid!"}), view)
        self.assertNotEqual(again.key, DIRS[(1, 0)])


class BlockedGoalTest(unittest.TestCase):
    def test_a_blocked_tile_is_not_a_goal(self) -> None:
        view = town_view((5, 5), (40, 40), dlvl=2)
        view.blocked = {(5, 4)}
        self.assertNotEqual(view.step_toward({(5, 4), (5, 8)}, avoid_monsters=True), (0, -1))
        self.assertIsNone(view.step_toward({(5, 4)}, avoid_monsters=True))


class LowHpTrapTest(unittest.TestCase):
    """Round 20: a level-1 character at 2 HP walked back over a known poison
    gas trap (frozen seed 1002)."""

    def test_known_traps_are_impassable_below_half_hp(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        view = town_view((5, 5), (40, 40), dlvl=1)
        view.types = [WALL] * (COLS * ROWS)
        for x in range(3, 12):
            view.types[5 * COLS + x] = 0x0
        view.types[5 * COLS + 6] = 0xE                       # known trap east
        view.types[5 * COLS + 10] = 0xA                      # the only way up is past it
        brain.food = 0                                       # resupply: head for the up stairs
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=1, clvl=1, hp=2, mhp=21), view)
        self.assertNotEqual(decision.key, DIRS[(1, 0)])
        brain.last_move = None
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=1, clvl=1, hp=21, mhp=21), view)
        # Healthy: the trap is only costly, so the path crosses it (disarming first, round 23).
        self.assertEqual((decision.key, brain.pending), (KEY_DISARM, DIRS[(1, 0)]))


class DisarmTest(unittest.TestCase):
    """Round 23: a known trap on the way is disarmed first; walking over an
    arrow trap again and again cost seed 1006 9,000 steps."""

    def corridor(self):
        view = town_view((5, 5), (9, 5), dlvl=2, stairs_type=0xA)
        view.types = [WALL] * (COLS * ROWS)
        for x in range(3, 10):
            view.types[5 * COLS + x] = 0x0
        view.types[5 * COLS + 6] = 0xE                       # known trap east
        view.types[5 * COLS + 9] = 0xA
        return view

    def test_disarms_a_trap_on_the_path_then_walks_on(self) -> None:
        brain = Brain(GOALS["reach_dl5"])
        brain.food = 0                                       # resupply: up stairs past the trap
        keys = []
        for _ in range(DISARM_TRIES + 1):
            brain.last_move = None                           # the fixture never moves
            keys.append(brain.decide(command_obs(pos=(5, 5), dlvl=2, clvl=3, hp=40, mhp=40),
                                     self.corridor()).key)
        self.assertEqual(keys, [KEY_DISARM] * DISARM_TRIES + [DIRS[(1, 0)]])
        self.assertEqual(brain.pending, None)


class SealedResupplyTest(unittest.TestCase):
    """Round 25: hungry in a pocket with only a down staircase, the bot
    searched walls until it starved (seed 1014). Down leads to a fresh level."""

    def pocket(self, unexplored=False):
        view = town_view((5, 5), (8, 5), dlvl=1, stairs_type=0x9)   # down stairs only
        view.types = [WALL] * (COLS * ROWS)
        for x in range(3, 9):
            view.types[5 * COLS + x] = 0x0
        view.types[5 * COLS + 8] = 0x9
        view.types[3 * COLS + 5] = UNKNOWN                   # space behind a wall: searchable
        if unexplored:
            view.types[4 * COLS + 4] = UNKNOWN
            view.types[4 * COLS + 3] = UNKNOWN
            view.types[5 * COLS + 2] = UNKNOWN
            view.types[5 * COLS + 3] = 0x0
        return view

    def test_hungry_and_no_way_up_takes_the_down_stairs(self) -> None:
        brain = Brain(GOALS["reach_dl5"])
        brain.food = 0
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=1, clvl=3), self.pocket())
        self.assertEqual((decision.layer, decision.key), ("resupply", DIRS[(1, 0)]))

    def test_unexplored_space_is_explored_first(self) -> None:
        brain = Brain(GOALS["reach_dl5"])
        brain.food = 0
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=1, clvl=3), self.pocket(unexplored=True))
        self.assertEqual(decision.layer, "explore")


class StandGroundTest(unittest.TestCase):
    """Round 28: fleeing 40 steps to far stairs under a caster's fire killed
    seed 1001; with the stairs far, a hurt player fights instead."""

    def room(self, stairs, glyph="p", level=2):
        view = town_view((5, 5), stairs, dlvl=2, monsters={(9, 5)}, stairs_type=0xA)
        view.creatures = {(9, 5): Creature(glyph, level)}    # a Novice Priest, as the messages say
        return view

    def test_far_stairs_still_flee_an_orc_but_not_an_orc_shaman(self) -> None:
        """M4 round 71: one Orc Shaman made every 'o' a caster, and the bot
        stood and fought whole Orc packs."""
        self.assertFalse(knowledge.casts("o", 6))           # Orc
        self.assertTrue(knowledge.casts("o", 9))            # Orc Shaman
        for level, layer in ((6, "retreat"), (9, "hunt")):
            brain = Brain(GOALS["reach_dl5"])
            brain.food = 3
            o = command_obs(pos=(5, 5), dlvl=2, clvl=8, hp=30, mhp=57, rows={0: "the Orc hits you."})
            self.assertEqual(brain.decide(o, self.room((5, 40), glyph="o", level=level)).layer, layer, level)

    def test_path_steps(self) -> None:
        view = town_view((5, 5), (40, 40), dlvl=2)
        self.assertEqual(view.path_steps({(9, 5)}, avoid_monsters=True), 4)
        self.assertEqual(view.path_steps({(5, 5)}, avoid_monsters=True), 0)

    def test_near_stairs_past_an_unknown_glyph_still_flee(self) -> None:
        """Review: the range compared weighted path cost, so stairs 3 steps
        away past an unidentified glyph looked 'far'."""
        brain = Brain(GOALS["reach_dl5"])
        brain.food = 3
        view = self.room((2, 5))
        view.types = [WALL] * (COLS * ROWS)
        for x in range(2, 10):
            view.types[5 * COLS + x] = 0x0
        view.types[5 * COLS + 2] = 0xA
        view.unknown = {(4, 4): "$"}                         # next to the only path
        brain.level.looked.add(((5, 5), (4, 4)))
        o = command_obs(pos=(5, 5), dlvl=2, clvl=4, hp=30, mhp=57, rows={0: "the Novice Priest casts a spell."})
        self.assertEqual(brain.decide(o, view).layer, "retreat")

    def test_near_stairs_still_flee(self) -> None:
        brain = Brain(GOALS["reach_dl5"])
        brain.food = 3
        o = command_obs(pos=(5, 5), dlvl=2, clvl=4, hp=30, mhp=57, rows={0: "the Novice Priest casts a spell."})
        self.assertEqual(brain.decide(o, self.room((2, 5))).layer, "retreat")

    def test_far_stairs_mean_fight_the_attacker(self) -> None:
        brain = Brain(GOALS["reach_dl5"])
        brain.food, brain.clw = 3, 5
        o = command_obs(pos=(5, 5), dlvl=2, clvl=4, hp=30, mhp=57, rows={0: "the Novice Priest casts a spell."})
        decision = brain.decide(o, self.room((5, 40)))
        self.assertEqual((decision.layer, decision.key), ("hunt", DIRS[(1, 0)]))

    def test_far_stairs_still_flee_a_melee_creature(self) -> None:
        """M4 round 34: a creature with no spells that follows spends its
        turns catching up; standing fought a Black Naga to the death."""
        brain = Brain(GOALS["reach_dl5"])
        brain.food = 3
        o = command_obs(pos=(5, 5), dlvl=2, clvl=4, hp=15, mhp=57, rows={0: "the Black Naga hits you."})
        self.assertEqual(brain.decide(o, self.room((5, 40), glyph="n")).layer, "retreat")


class RestockHopTest(unittest.TestCase):
    """M3 round 15: stores restock on every return to town, so with no food
    for sale a player hops down to DL1 and straight back up."""

    MENU = {3: " a) Iron Spike                 1 GP", 19: " B)uy  S)ell  Q)uit  Gold: 200"}

    def test_an_empty_store_means_a_hop_then_a_wait(self) -> None:
        brain = Brain(GOALS["reach_dl5"])
        brain.food = 0
        for _ in range(RESTOCK_HOPS):
            brain.shopped = False
            self.assertEqual(brain.decide(BrainM2Test.store_obs(BrainM2Test(), "menu", self.MENU), None).key,
                             ord("Q"))
            self.assertEqual(brain.resupply_after, 0)     # come straight back
        brain.shopped = False
        brain.decide(BrainM2Test.store_obs(BrainM2Test(), "menu", self.MENU), None)
        self.assertGreater(brain.resupply_after, 0)       # then keep playing a while

    def test_a_refused_purchase_still_counts_the_visit(self) -> None:
        """Round 20: out of gold, every visit ended on "You cannot afford
        that." and the bot hopped for 15,000 steps (seed 1006)."""
        brain = Brain(GOALS["reach_dl5"])
        brain.light_left, brain.torches = 0, 0              # out of light, no spare torch
        menu = {**self.MENU, 4: " b) Wooden Torch (134 turns)   2 GP", 19: " B)uy  S)ell  Q)uit  Gold: 200"}
        refused = {**menu, 22: " You cannot afford that."}
        for _ in range(RESTOCK_HOPS + 1):
            brain.shopped = False
            store = BrainM2Test.store_obs
            brain.decide(store(BrainM2Test(), "menu", menu), None)
            brain.decide(store(BrainM2Test(), "buy_which", menu), None)
            brain.decide(store(BrainM2Test(), "message", refused), None)
            brain.decide(store(BrainM2Test(), "menu", menu), None)
        self.assertGreater(brain.resupply_after, 0)

    def test_the_hop_climbs_straight_back_from_dl1(self) -> None:
        brain = Brain(GOALS["reach_dl5"])
        brain.food = 0
        view = town_view((5, 5), (5, 5), dlvl=1, stairs_type=0xA)   # arrived on the up stairs
        self.assertEqual(brain.decide(command_obs(pos=(5, 5), dlvl=1, clvl=2), view).key, ord("<"))


class StationaryMemoryTest(unittest.TestCase):
    """M3 round 15: a creature that never moves is still there when out of
    sight (a Floating Eye in a dark corridor caused two-tile oscillations)."""

    def corridor(self, creatures):
        view = town_view((5, 5), (12, 5), dlvl=2)
        view.types = [WALL] * (COLS * ROWS)
        for x in range(1, 13):
            view.types[5 * COLS + x] = 0x0
        view.types[5 * COLS + 12] = 0xA                      # up stairs at the east end
        view.creatures = creatures
        return view

    def test_a_stationary_creature_out_of_sight_still_blocks_the_path(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        brain.food = 0                                       # resupply: head for the up stairs
        # A strong one (lore: 67 HP at level 6): a weak one in the only way
        # on is now killed instead (SealedHazardTest).
        brain.decide(command_obs(pos=(5, 5), dlvl=2, clvl=3), self.corridor({(8, 5): Creature("m", 6)}))
        view = self.corridor({})
        view.pos = (4, 5)
        decision = brain.decide(command_obs(pos=(4, 5), dlvl=2, clvl=3), view)
        self.assertNotEqual(decision.key, DIRS[(1, 0)])      # not back toward the mold

    def test_it_is_forgotten_when_the_player_stands_next_to_an_empty_spot(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        brain.decide(command_obs(pos=(5, 5), dlvl=2, clvl=3), self.corridor({(8, 5): Creature("e", 1)}))
        view = self.corridor({})
        view.pos = (7, 5)
        brain.decide(command_obs(pos=(7, 5), dlvl=2, clvl=3), view)
        self.assertEqual(brain.level.stationary, {})

    def test_a_weak_one_blocking_the_only_way_on_is_attacked(self) -> None:
        """M4 round 70: seed 1021 rested 9,600 turns behind a Floating Eye in
        the only corridor and starved."""
        brain = Brain(GOALS["reach_dl5"])
        brain.food = 3
        view = self.corridor({(8, 5): Creature("e", 1)})
        view.pos = (7, 5)
        decision = brain.decide(command_obs(pos=(7, 5), dlvl=2, clvl=3, hp=40, mhp=40), view)
        self.assertEqual((decision.layer, decision.key), ("fight", DIRS[(1, 0)]))

    def test_one_beside_the_only_door_out_of_a_room_is_attacked(self) -> None:
        """M4 round 73: seed 1006 searched a room for 12,000 turns: a
        Floating Eye stood beside its only door, and an edge next to a
        hazard is no frontier, so the room looked sealed."""
        brain = Brain(GOALS["clvl10"])
        brain.food = 3
        view = town_view((5, 5), (40, 40), dlvl=2)
        view.types = [WALL] * (COLS * ROWS)
        for x in range(3, 9):
            for y in range(3, 7):
                view.types[y * COLS + x] = 0x0               # the room
        view.types[7 * COLS + 6] = 0x0                       # its door square, below (6, 6)
        view.types[8 * COLS + 6] = UNKNOWN                   # unexplored beyond
        view.creatures = {(6, 6): Creature("e", 1)}          # the eye beside the door
        view.pos = (5, 5)
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=2, clvl=4, hp=40, mhp=40), view)
        self.assertEqual((decision.layer, decision.key), ("fight", DIRS[(1, 1)]))

    def test_the_blocker_chosen_is_kept_until_it_is_gone(self) -> None:
        """2026-11-06: a step toward the blocker stood where a path past it
        counted (the start may be beside a monster), so clear_way stood down,
        a search walked back, and the next step came again: four games
        entered one square 100 times in 550-830 steps."""
        brain = Brain(GOALS["reach_dl5"])
        brain.food = 3
        view = self.corridor({(8, 5): Creature("e", 1)})
        view.pos = (5, 5)
        first = brain.clear_way(command_obs(pos=(5, 5), dlvl=2, clvl=3, hp=40, mhp=40), view)
        self.assertEqual((first.layer, brain.level.clear_target), ("fight", (8, 5)))
        view.pos = (6, 5)
        view.types[5 * COLS + 4] = 0xA                       # stairs up behind: a way out now counts
        nxt = brain.clear_way(command_obs(pos=(6, 5), dlvl=2, clvl=3, hp=40, mhp=40), view)
        self.assertEqual((nxt.layer, nxt.reason), ("fight", "the 'e' blocks the only way on: approach it"))
        eye = view.creatures[(8, 5)]
        view.creatures = {}                                  # out of the light, but remembered
        brain.level.stationary[(8, 5)] = eye
        held = brain.clear_way(command_obs(pos=(6, 5), dlvl=2, clvl=3, hp=40, mhp=40), view)
        self.assertEqual((held.layer, brain.level.clear_target), ("fight", (8, 5)))
        brain.level.stationary.clear()                       # killed: the commitment goes
        self.assertIsNone(brain.clear_way(command_obs(pos=(6, 5), dlvl=2, clvl=3, hp=40, mhp=40), view))
        self.assertIsNone(brain.level.clear_target)

    def test_a_chosen_blocker_comes_before_other_walks(self) -> None:
        """2026-11-06: from beside a ',' a path past it counted, explore (or
        the walk for light) stepped away, and clear_way walked back: 91
        approaches on DL19, 92 on DL1."""
        brain = Brain(GOALS["reach_dl5"])
        brain.food = 3
        view = self.corridor({(8, 5): Creature("e", 1)})
        view.pos = (5, 5)
        o = command_obs(pos=(5, 5), dlvl=2, clvl=3, hp=40, mhp=40)
        view.types[5 * COLS + 3] = UNKNOWN                   # an edge behind the player
        self.assertEqual(brain.decide(o, view).layer, "explore")    # a walk away there is
        self.assertIsNone(brain.chosen_blocker(o, view))            # nothing chosen
        brain.level.clear_target = (8, 5)
        decision = brain.decide(o, view)                            # chosen: before explore
        self.assertEqual((decision.layer, decision.reason), ("fight", "the 'e' blocks the only way on: approach it"))
        brain.level.clear_target = (9, 9)                           # gone
        self.assertIsNone(brain.chosen_blocker(o, view))

    def test_the_last_step_to_a_chosen_blocker_is_taken(self) -> None:
        """2026-11-06: one step short of the squares beside a ',', a path
        that avoids monsters found none, the commitment went and a search
        walked back: 95 times."""
        from unittest import mock
        brain = Brain(GOALS["reach_dl5"])
        brain.food = 3
        view = self.corridor({(8, 5): Creature("e", 1)})
        view.pos = (6, 5)
        brain.level.clear_target = (8, 5)
        real = view.step_toward

        def refusing(goals, *, avoid_monsters, **kw):
            return None if avoid_monsters else real(goals, avoid_monsters=False, **kw)
        with mock.patch.object(view, "step_toward", side_effect=refusing):
            decision = brain.clear_way(command_obs(pos=(6, 5), dlvl=2, clvl=3, hp=40, mhp=40), view)
        self.assertEqual((decision.layer, decision.key), ("fight", DIRS[(1, 0)]))
        self.assertEqual(brain.level.clear_target, (8, 5))

    def test_a_walk_to_a_staircase_keeps_its_path(self) -> None:
        """2026-11-06: replanned each step, the way to the up stairs flipped
        as remembered and perilous squares came and went: a level-15
        Halfling walked between x=109 and x=120 300 times on DL4."""
        from unittest import mock
        brain = Brain(GOALS["reach_dl5"])
        view = town_view((5, 5), (1, 5), dlvl=2, stairs_type=0xA)
        self.assertEqual(brain.committed_step(view, {(1, 5)}), (-1, 0))
        self.assertEqual(brain.level.route[-1], (1, 5))
        view.pos = (4, 5)
        with mock.patch.object(view, "step_toward", return_value=(1, 0)) as replan:   # the way flips
            self.assertEqual(brain.committed_step(view, {(1, 5)}), (-1, 0))         # the kept path goes on
            replan.assert_not_called()
            view.creatures = {(3, 5): Creature("k", 1)}                            # its next square taken
            self.assertEqual(brain.committed_step(view, {(1, 5)}), (1, 0))
            replan.assert_called_once()

    def test_a_strong_one_blocking_the_only_way_on_is_left(self) -> None:
        brain = Brain(GOALS["reach_dl5"])
        brain.food = 3
        view = self.corridor({(8, 5): Creature("m", 6)})     # lore: 67 HP at level 6
        view.pos = (7, 5)
        decision = brain.decide(command_obs(pos=(7, 5), dlvl=2, clvl=3, hp=40, mhp=40), view)
        self.assertNotEqual(decision.layer, "fight")

    def test_one_with_a_way_around_is_left(self) -> None:
        brain = Brain(GOALS["reach_dl5"])
        brain.food = 3
        view = town_view((6, 5), (12, 5), dlvl=2, stairs_type=0xA)
        view.creatures = {(8, 5): Creature("e", 1)}          # two squares off: not gazing yet
        decision = brain.decide(command_obs(pos=(6, 5), dlvl=2, clvl=3, hp=40, mhp=40), view)
        self.assertNotEqual(decision.layer, "fight")

    def test_a_weak_eye_beside_the_player_is_killed(self) -> None:
        """M4 round 78: beside a Floating Eye the bot was paralysed every turn
        while Creeping Coins fed (seeds 1026, 1040)."""
        brain = Brain(GOALS["reach_dl5"])
        brain.food = 3
        view = town_view((7, 5), (12, 5), dlvl=2, stairs_type=0xA)
        view.creatures = {(8, 5): Creature("e", 1), (5, 5): Creature("$", 4)}
        decision = brain.decide(command_obs(pos=(7, 5), dlvl=2, clvl=3, hp=40, mhp=40), view)
        self.assertEqual((decision.layer, decision.key), ("fight", DIRS[(1, 0)]))

    def test_explore_never_steps_back_beside_coins(self) -> None:
        """M4 round 78: seed 1026 alternated walking away from Creeping Coins
        and exploring back into them."""
        brain = Brain(GOALS["reach_dl5"])
        brain.food = 3
        o = command_obs(pos=(5, 5), dlvl=2, clvl=3, hp=40, mhp=40)
        view = town_view((5, 5), (40, 40), dlvl=2)
        for y in range(ROWS):
            view.types[y * COLS + 12] = UNKNOWN              # the unexplored edge: east
        self.assertIsNotNone(brain.explore(o, view))         # control: it goes east
        view.creatures = {(7, 5): Creature("$", 4)}          # every first step east passes beside them
        self.assertIsNone(brain.explore(o, view))
        view.creatures = {}                                   # out of the light, but remembered
        brain.level.slow_seen[(7, 5)] = o.step
        self.assertIsNone(brain.explore(o, view))

    def test_explore_never_steps_back_beside_a_worm_mass(self) -> None:
        """M5 regression, seed 1006: by kind, a White Worm mass too ('w' is
        shared with the fast Giant Purple Worm)."""
        brain = Brain(GOALS["reach_dl5"])
        brain.food = 3
        o = command_obs(pos=(5, 5), dlvl=2, clvl=3, hp=40, mhp=40)
        view = town_view((5, 5), (40, 40), dlvl=2)
        for y in range(ROWS):
            view.types[y * COLS + 12] = UNKNOWN              # the unexplored edge: east
        view.creatures = {(7, 5): Creature("w", 1)}          # every first step east passes beside it
        self.assertIsNone(brain.explore(o, view))
        view.creatures = {(7, 5): Creature("w", 29)}         # a Giant Purple Worm is no slow kind
        self.assertIsNotNone(brain.explore(o, view))

    def test_no_clearing_a_blocker_with_something_else_coming(self) -> None:
        brain = Brain(GOALS["reach_dl5"])
        brain.food = 3
        o = command_obs(pos=(7, 5), dlvl=2, clvl=3, hp=40, mhp=40)
        calm = self.corridor({(9, 5): Creature("e", 1)})
        calm.pos = (7, 5)
        self.assertIsNotNone(brain.clear_way(o, calm))      # control: it would go
        coming = self.corridor({(9, 5): Creature("e", 1), (4, 5): Creature("k", 1)})
        coming.pos = (7, 5)
        self.assertTrue(brain.clear_way(o, coming).reason.endswith("wait, something moves near it"))   # chosen by the control: wait

    def test_a_committed_blocker_is_judged_calm_from_where_it_stands(self) -> None:
        """2026-11-06: calm measured from the player, each step toward the
        ',' brought a mover into range and a search walked back out."""
        brain = Brain(GOALS["reach_dl5"])
        brain.food = 3
        view = self.corridor({(9, 5): Creature("e", 1), (1, 5): Creature("k", 1)})
        view.pos = (6, 5)                                     # the 'k' is 5 from here, 8 from the eye
        brain.level.clear_target = (9, 5)
        decision = brain.clear_way(command_obs(pos=(6, 5), dlvl=2, clvl=3, hp=40, mhp=40), view)
        self.assertEqual((decision.layer, decision.reason), ("fight", "the 'e' blocks the only way on: approach it"))
        view.creatures[(5, 5)] = Creature("k", 1)             # one close to the eye: not now
        self.assertTrue(brain.clear_way(command_obs(pos=(6, 5), dlvl=2, clvl=3, hp=40, mhp=40), view).reason.endswith("wait, something moves near it"))   # chosen: wait, not go

    def test_a_blocker_is_approached_by_squares_that_can_be_stood_on(self) -> None:
        """2026-11-06: a path takes a goal square as reached whatever it is:
        a level-1 Warrior walked into the wall beside a ',' 200 times in 825
        steps, the ',' in a corridor below it."""
        brain = Brain(GOALS["reach_dl5"])
        brain.food = 3
        view = town_view((5, 3), (40, 40), dlvl=2)
        view.types = [WALL] * (COLS * ROWS)
        for x in range(2, 12):
            view.types[3 * COLS + x] = 0x0                    # the upper corridor, the player in it
            view.types[5 * COLS + x] = 0x0                    # the lower one, the ',' in it
        view.types[5 * COLS + 1] = 0x0
        view.types[4 * COLS + 1] = 0x0                        # joined at the west end
        view.types[3 * COLS + 1] = 0x0
        view.creatures = {(4, 5): Creature(",", 1)}
        view.pos = (5, 3)
        brain.level.clear_target = (4, 5)
        decision = brain.clear_way(command_obs(pos=(5, 3), dlvl=2, clvl=1, hp=19, mhp=19), view)
        self.assertEqual(decision.key, DIRS[(-1, 0)])         # west along it, not into the wall at (4, 4)

    def test_a_slow_creature_near_a_blocker_matters_only_beside_a_gaze(self) -> None:
        """2026-11-06: worm masses wandering near a ',' turned characters back
        from it 100 times in 400-1,200 steps; the calm rule is for a
        paralysing eye (M4 round 78: Creeping Coins ate a paralysed bot)."""
        brain = Brain(GOALS["reach_dl5"])
        brain.food = 3
        o = command_obs(pos=(6, 5), dlvl=2, clvl=3, hp=40, mhp=40)
        view = self.corridor({(9, 5): Creature(",", 1), (5, 5): Creature("w", 1)})   # a White Worm mass
        view.pos = (6, 5)
        brain.level.clear_target = (9, 5)
        decision = brain.clear_way(o, view)
        self.assertEqual((decision.layer, decision.reason), ("fight", "the ',' blocks the only way on: approach it"))
        view.creatures[(9, 5)] = Creature("e", 1)                      # an eye: the worm matters
        self.assertTrue(brain.clear_way(o, view).reason.endswith("wait, something moves near it"))   # chosen: wait for it

    def test_a_slow_creature_in_the_only_way_is_cleared(self) -> None:
        """C128, 2026-11-07: a slow creature in a corridor turned a Warrior
        back and forth 300 times; it is killed like a blocker that never moves."""
        brain = Brain(GOALS["reach_dl5"])
        brain.food = 3
        view = self.corridor({(8, 5): Creature("w", 1)})          # a White Worm mass
        view.pos = (5, 5)
        decision = brain.clear_way(command_obs(pos=(5, 5), dlvl=2, clvl=10, hp=80, mhp=80), view)
        self.assertEqual((decision.layer, brain.level.clear_target), ("fight", (8, 5)))

    def test_a_blocker_is_attacked_from_range_whatever_moves_near_it(self) -> None:
        """Maintainer, 2026-11-07: "kill all the monsters with all the tools we
        have available": an eye's gaze holds only what stands beside it, so a
        flask or a bolt from here, not a wait while lice wander near."""
        from moria_playtest.brain import KEY_THROW
        from moria_playtest.magic import Prayer
        brain = Brain(GOALS["reach_dl5"])
        brain.food, brain.oil, brain.lamp = 3, 4, False
        view = self.corridor({(9, 5): Creature("e", 1), (10, 5): Creature("k", 1)})   # something by the eye
        view.pos = (6, 5)
        brain.level.clear_target = (9, 5)
        o = command_obs(pos=(6, 5), dlvl=2, clvl=3, hp=40, mhp=40)
        decision = brain.clear_way(o, view)
        self.assertEqual((decision.key, decision.reason), (KEY_THROW, "the 'e' blocks the way: throw oil at it"))
        mage = Brain(GOALS["reach_dl5"])
        mage.food, mage.magic.study_due, mage.magic.listed = 3, False, True
        mage.magic.mage = True
        mage.magic.known = {"Magic Missile": Prayer("a", 1, 1, "Magic for Beginners")}
        mage.level.clear_target = (9, 5)
        o = command_obs(pos=(6, 5), dlvl=2, clvl=3, hp=40, mhp=40, rows={23: "HP:40/40 MP:5/5 AC:5 AU:30"})
        self.assertEqual(mage.clear_way(o, view).reason, "the 'e' blocks the way: cast Magic Missile at it")

    def test_a_chosen_blocker_is_waited_for_then_left_a_while(self) -> None:
        """2026-11-06: worm masses wandering by an eye showed and hid, and the
        bot walked off and back, 81 approaches and 75 stair walks in 571
        steps. It waits there instead, then leaves that blocker a while."""
        from moria_playtest.brain import CLEAR_HOLD, CLEAR_SKIP, KEY_REST
        brain = Brain(GOALS["reach_dl5"])
        brain.food = 3
        view = self.corridor({(9, 5): Creature("e", 1), (5, 5): Creature("k", 1)})   # a kobold by the eye
        view.pos = (6, 5)
        brain.level.clear_target = (9, 5)
        o = command_obs(pos=(6, 5), dlvl=2, clvl=3, hp=40, mhp=40)
        calm = self.corridor({(9, 5): Creature("e", 1)})
        calm.pos = (6, 5)
        for n in range(CLEAR_HOLD):
            self.assertEqual(brain.clear_way(o, view).key, KEY_REST)
            if n % 3 == 0:
                brain.clear_way(o, calm)                         # a calm step between: still counted
        self.assertIsNone(brain.clear_way(o, view))              # given up a while
        self.assertIsNone(brain.level.clear_target)
        self.assertEqual(brain.level.clear_skip[(9, 5)], o.step + CLEAR_SKIP)

    def test_one_standing_still_near_a_blocker_is_not_coming(self) -> None:
        """C64 Balrog, 2026-11-06: a giant on one square, seen only from
        inside the room, turned a level-23 Gnome back from an eye 100 times
        in 850 steps."""
        from moria_playtest.brain import STILL_STEPS
        brain = Brain(GOALS["reach_dl5"])
        brain.food = 3
        view = self.corridor({(9, 5): Creature("e", 1), (5, 5): Creature("k", 1)})
        view.pos = (6, 5)
        brain.level.clear_target = (9, 5)
        o = command_obs(pos=(6, 5), dlvl=2, clvl=3, hp=40, mhp=40)
        brain.level.still[(5, 5)] = ("k", 0)
        o.step = STILL_STEPS - 1
        self.assertTrue(brain.clear_way(o, view).reason.endswith("wait, something moves near it"))           # not long enough: wait
        o.step = STILL_STEPS
        decision = brain.clear_way(o, view)                    # asleep: not coming
        self.assertEqual((decision.layer, decision.reason), ("fight", "the 'e' blocks the only way on: approach it"))

    def test_a_creature_seen_elsewhere_has_moved(self) -> None:
        brain = Brain(GOALS["reach_dl5"])
        brain.food = 3
        view = self.corridor({(5, 5): Creature("k", 1)})
        view.pos = (2, 5)
        o = command_obs(pos=(2, 5), dlvl=2, clvl=3, hp=40, mhp=40)
        brain.decide(o, view)
        self.assertEqual(brain.level.still, {(5, 5): ("k", o.step)})
        view.creatures = {(4, 5): Creature("k", 1)}
        o.step += 5
        brain.decide(o, view)
        self.assertEqual(brain.level.still, {(4, 5): ("k", o.step)})

    def test_hurt_rests_and_does_not_flee_from_a_distant_stationary_creature(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        brain.food = 3
        view = self.corridor({(8, 5): Creature("e", 1)})
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=1, clvl=3, hp=20, mhp=40), view)
        self.assertEqual((decision.layer, decision.key), ("rest", KEY_AUTOREST))


class FearTest(unittest.TestCase):
    """M3 round 10: too afraid to melee means do not try; get away instead."""

    def afraid_obs(self):
        o = command_obs(pos=(5, 5), dlvl=3, clvl=3, hp=40, mhp=40)
        o.rows[0] = "You are too afraid!".ljust(40)
        return o

    def test_afraid_with_a_creature_adjacent_runs_for_the_stairs(self) -> None:
        brain = Brain(GOALS["reach_clvl2"])
        view = town_view((5, 5), (5, 2), dlvl=3, monsters={(6, 5)}, stairs_type=0xA)
        decision = brain.decide(self.afraid_obs(), view)
        self.assertEqual(decision.layer, "retreat")

    def test_afraid_throws_before_running(self) -> None:
        """M4 round 2 (§15.3): a fast attacker (Poltergeist) follows a runner;
        fear blocks melee, not throwing."""
        brain = Brain(GOALS["reach_clvl2"])
        brain.oil = 3
        view = town_view((5, 5), (5, 2), dlvl=3, monsters={(6, 5)}, stairs_type=0xA)
        decision = brain.decide(self.afraid_obs(), view)
        self.assertEqual(decision.layer, "throw")

    def test_afraid_never_chooses_melee(self) -> None:
        brain = Brain(GOALS["reach_clvl2"])
        view = town_view((5, 5), (40, 40), dlvl=3, monsters={(6, 5)})
        self.assertNotIn(brain.decide(self.afraid_obs(), view).layer, ("fight", "hunt"))

    def test_fear_wears_off(self) -> None:
        brain = Brain(GOALS["reach_clvl2"])
        view = town_view((5, 5), (40, 40), dlvl=3, monsters={(6, 5)})
        brain.decide(self.afraid_obs(), view)
        o = command_obs(pos=(5, 5), dlvl=3, clvl=3, hp=40, mhp=40)
        o.rows[0] = "You feel bolder now.".ljust(40)
        self.assertEqual(brain.decide(o, view).layer, "fight")


class FastAttackerTest(unittest.TestCase):
    """M3 round 14: fear shown on a -more- screen counts; never run on foot
    from a creature faster than the player."""

    def test_fear_on_a_more_screen_blocks_melee(self) -> None:
        brain = Brain(GOALS["reach_clvl2"])
        more = command_obs(pos=(5, 5), dlvl=3, clvl=3, hp=40, mhp=40,
                           rows={0: "You are too afraid!", 1: "the Kobold hits you. -more-"})
        more.mode, more.stage = Mode.DISMISS, "more"
        self.assertEqual(brain.decide(more, None).key, KEY_SPACE)
        view = town_view((5, 5), (40, 40), dlvl=3, monsters={(6, 5)})
        o = command_obs(pos=(5, 5), dlvl=3, clvl=3, hp=40, mhp=40, rows={0: "the Kobold hits you."})
        self.assertNotIn(brain.decide(o, view).layer, ("fight", "hunt"))

    def test_the_last_fear_message_on_a_screen_wins(self) -> None:
        brain = Brain(GOALS["reach_clvl2"])
        brain.afraid = 3
        more = command_obs(rows={0: "You are too afraid!", 1: "You feel bolder now. -more-"})
        more.mode, more.stage = Mode.DISMISS, "more"
        brain.decide(more, None)
        self.assertEqual(brain.afraid, 0)

    def test_fights_a_fast_attacker_instead_of_running(self) -> None:
        brain = Brain(GOALS["reach_clvl2"])
        view = town_view((5, 5), (5, 1), dlvl=3, monsters={(6, 5)}, stairs_type=0xA)
        view.creatures = {(6, 5): Creature("G", 3)}          # the Poltergeist, drawn as it is
        o = command_obs(pos=(5, 5), dlvl=3, clvl=3, hp=20, mhp=40, rows={0: "the Poltergeist hits you."})
        self.assertEqual(brain.decide(o, view).layer, "fight")
        view.creatures = {(6, 5): Creature("k", 1)}
        o = command_obs(pos=(5, 5), dlvl=3, clvl=3, hp=20, mhp=40, rows={0: "the Kobold hits you."})
        self.assertEqual(brain.decide(o, view).layer, "retreat")

    def test_an_unseen_fast_attacker_is_still_fled(self) -> None:
        """Round 21: an invisible Poltergeist cannot be fought; standing
        still searching let it kill the player (seed 1013)."""
        brain = Brain(GOALS["reach_clvl2"])
        brain.food = 3
        view = town_view((5, 5), (5, 1), dlvl=3, stairs_type=0xA)
        o = command_obs(pos=(5, 5), dlvl=3, clvl=4, hp=20, mhp=40, rows={0: "the Poltergeist hits you."})
        self.assertEqual(brain.decide(o, view).layer, "retreat")

    def test_a_creature_that_beat_the_bot_is_tough(self) -> None:
        """M4 rounds 52-54: Green Nagas won fight after fight."""
        brain = Brain(GOALS["reach_clvl2"])
        brain.food = 3
        view = town_view((5, 5), (5, 1), dlvl=3, monsters={(6, 5)}, stairs_type=0xA)
        view.creatures = {(6, 5): Creature("n", 3)}
        o = command_obs(pos=(5, 5), dlvl=3, clvl=5, hp=40, mhp=40)
        brain.decide(o, view)
        o = command_obs(pos=(5, 5), dlvl=3, clvl=5, hp=18, mhp=40, rows={0: "the Green Naga hits you."})
        o.step = 1
        brain.decide(o, view)
        self.assertIn("Green Naga", brain.tough)
        self.assertFalse(brain.engageable(Creature("n", 3), o))
        o = command_obs(pos=(5, 5), dlvl=3, clvl=5, hp=30, mhp=40)   # 75%: retreat early
        o.step = 2
        self.assertEqual(brain.decide(o, view).layer, "retreat")
        # Three levels on, and armed to win (M5a: fight_odds also decides).
        brain.weapon = ("Broad Sword", 0)
        o = command_obs(pos=(5, 5), dlvl=3, clvl=8, hp=70, mhp=70,
                        rows={19: "ST:18/50 DX:12", 23: "HP:70/70  MP:0/0   AC:20  AU:277"})
        self.assertTrue(brain.engageable(Creature("n", 3), o))

    def test_monster_lore_marks_a_naga_too_strong_early(self) -> None:
        """M4 rounds 52-62: a Green Naga (40 HP, AC 40) killed characters
        on their first meeting; kobolds stay fair game."""
        brain = Brain(GOALS["clvl10"])
        o = command_obs(pos=(5, 5), dlvl=5, clvl=5)
        self.assertTrue(brain.too_strong(Creature("n", 5), o))
        self.assertFalse(Brain(GOALS["reach_dl8"]).too_strong(Creature("n", 5), o))   # depth goals dive
        self.assertFalse(brain.engageable(Creature("n", 5), o))
        self.assertFalse(brain.too_strong(Creature("k", 1), command_obs(pos=(5, 5), dlvl=1, clvl=1)))
        # Outgrown at level 7 with the strength and weapon to win (M5a: the
        # odds are the character's own melee, fight_odds).
        brain.weapon = ("Broad Sword", 0)
        strong = command_obs(pos=(5, 5), dlvl=5, clvl=7, hp=80, mhp=80,
                             rows={19: "ST:18/50 DX:12", 23: "HP:80/80  MP:0/0   AC:20  AU:277"})
        self.assertFalse(brain.too_strong(Creature("n", 5), strong))

    def test_a_retreat_from_an_unseen_attacker_keeps_going(self) -> None:
        """M4 round 46b: the turn after an unseen Green Naga hit, explore
        walked back to it; ten such round trips killed seed 1011."""
        brain = Brain(GOALS["reach_clvl2"])
        brain.food = 3
        view = town_view((5, 5), (5, 1), dlvl=3, stairs_type=0xA)
        o = command_obs(pos=(5, 5), dlvl=3, clvl=4, hp=20, mhp=40, rows={0: "the Green Naga hits you."})
        self.assertEqual(brain.decide(o, view).layer, "retreat")
        view = town_view((5, 4), (5, 1), dlvl=3, stairs_type=0xA)
        o = command_obs(pos=(5, 4), dlvl=3, clvl=4, hp=20, mhp=40)
        o.step = 1
        self.assertEqual(brain.decide(o, view).layer, "retreat")

    def test_a_retreat_keeps_going_when_its_creature_drops_out_of_sight(self) -> None:
        """M4 round 47: a slow coin two squares off in the dark is not drawn;
        explore stepped back beside it every other turn (seed 1017)."""
        brain = Brain(GOALS["reach_clvl2"])
        brain.food = 3
        view = town_view((5, 5), (5, 1), dlvl=3, monsters={(5, 6)}, stairs_type=0xA)
        o = command_obs(pos=(5, 5), dlvl=3, clvl=4, hp=30, mhp=40)
        self.assertEqual(brain.decide(o, view).layer, "retreat")
        view = town_view((5, 4), (5, 1), dlvl=3, stairs_type=0xA)
        o = command_obs(pos=(5, 4), dlvl=3, clvl=4, hp=30, mhp=40)
        o.step = 1
        self.assertEqual(brain.decide(o, view).layer, "retreat")

    def test_a_caster_heard_that_could_kill_sends_the_character_upstairs(self) -> None:
        """M5f round 6: a Novice Mage blinked out of the light and hit a
        Gnome Priest from 24 HP to 8 (Cause Light Wounds, 3d8), then killed
        it with the next."""
        brain = Brain(GOALS["clvl10"])
        brain.food = 3
        view = town_view((5, 5), (20, 5), dlvl=2, stairs_type=0xA)
        view.creatures = {(5, 15): Creature("p", 2)}                   # a Novice Mage, seen far off
        brain.decide(command_obs(pos=(5, 5), dlvl=2, clvl=3, hp=29, mhp=29), view)
        view = town_view((5, 5), (20, 5), dlvl=2, stairs_type=0xA)     # gone into the dark
        hurt = command_obs(pos=(5, 5), dlvl=2, clvl=3, hp=20, mhp=29)
        hurt.step = 5
        self.assertEqual(brain.decide(hurt, view).layer, "leave-caster")
        two = command_obs(pos=(5, 5), dlvl=2, clvl=3, hp=30, mhp=49)
        two.step = 6
        self.assertEqual(brain.decide(two, view).layer, "leave-caster")       # one cast cannot, two can (round 8)
        strong = command_obs(pos=(5, 5), dlvl=2, clvl=3, hp=49, mhp=49)
        strong.step = 6
        self.assertNotEqual(brain.decide(strong, view).layer, "leave-caster")   # two casts (48) cannot kill
        later = command_obs(pos=(5, 5), dlvl=2, clvl=3, hp=20, mhp=29)
        later.step = 200
        self.assertNotEqual(brain.decide(later, view).layer, "leave-caster")  # long gone (CASTER_MEMORY)
        heard = Brain(GOALS["clvl10"])                                      # heard, never seen
        heard.decide(command_obs(pos=(5, 5), dlvl=2, clvl=3, hp=29, mhp=29,
                                 rows={0: "the Novice Mage casts a spell."}), view)
        self.assertIn(("p", 2), heard.level.casters)
        scared = Brain(GOALS["clvl10"])                                     # round 8, seed 1008
        scared.decide(command_obs(pos=(5, 5), dlvl=2, clvl=3, hp=29, mhp=29,
                                  rows={0: "the Novice Priest frightens you."}), view)
        self.assertIn(("p", 2), scared.level.casters)

    def test_a_retreat_runs_all_the_way_to_the_stairs(self) -> None:
        """M5f baseline: a Large Brown Snake dropped out of the light; after
        NEAR_STEPS the bot auto-rested on the way and was bitten at each of
        three rests (Elf Ranger, seed 1008)."""
        brain = Brain(GOALS["reach_clvl2"])
        brain.food = 3
        view = town_view((5, 5), (30, 5), dlvl=3, monsters={(5, 6)}, stairs_type=0xA)
        o = command_obs(pos=(5, 5), dlvl=3, clvl=4, hp=20, mhp=40)
        self.assertEqual(brain.decide(o, view).layer, "retreat")
        for step in range(1, 11):                                   # nothing in view, twice NEAR_STEPS
            view = town_view((5 + step, 5), (30, 5), dlvl=3, stairs_type=0xA)
            o = command_obs(pos=(5 + step, 5), dlvl=3, clvl=4, hp=20, mhp=40)
            o.step = step
            self.assertEqual(brain.decide(o, view).layer, "retreat", f"step {step}")

    def test_no_searching_while_something_unseen_attacks(self) -> None:
        brain = Brain(GOALS["reach_dl5"])
        brain.food = 3
        view = town_view((7, 5), (40, 40), dlvl=3)
        view.types = [WALL] * (COLS * ROWS)
        for x in range(3, 8):
            view.types[5 * COLS + x] = 0x0                 # a dead-end corridor ...
        view.types[5 * COLS + 9] = UNKNOWN                 # ... with unexplored space past its end
        view.types[5 * COLS + 3] = 0xA
        prepared(brain)
        o = command_obs(pos=(7, 5), dlvl=3, clvl=4, hp=50, mhp=50)
        self.assertEqual(brain.decide(o, view).layer, "search")   # unattacked: search here
        brain = Brain(GOALS["reach_dl5"])
        brain.food = 3
        prepared(brain)
        o = command_obs(pos=(7, 5), dlvl=3, clvl=4, hp=50, mhp=50, rows={0: "the Poltergeist hits you."})
        self.assertNotEqual(brain.decide(o, view).layer, "search")

    def test_afraid_throws_oil_at_an_adjacent_creature(self) -> None:
        """Round 22: fear blocks melee only; a cornered player throws (seed
        1013: a Poltergeist kept the player afraid in a dead end)."""
        brain = Brain(GOALS["reach_dl5"])
        brain.food, brain.oil = 3, 2
        view = town_view((5, 5), (40, 40), dlvl=3, monsters={(5, 6)})
        o = command_obs(pos=(5, 5), dlvl=3, clvl=4, hp=30, mhp=40, rows={0: "You are too afraid!"})
        decision = brain.decide(o, view)
        self.assertEqual((decision.layer, decision.key), ("throw", KEY_THROW))
        prompt = command_obs(pos=(5, 5), rows={0: "Throw which item (a-c)?"})
        prompt.mode, prompt.stage = Mode.ITEM, "which"
        self.assertEqual(brain.decide(prompt, None).key, ord("?"))
        listed = command_obs(pos=(5, 5), rows={1: " a) Ration of Food", 2: " b) Flask of Oil (250 turns)"})
        listed.mode, listed.stage = Mode.ITEM, "list"
        self.assertEqual(brain.decide(listed, None).key, ord("B"))
        direction = command_obs(pos=(5, 5), rows={0: "Direction?"})
        direction.mode, direction.stage = Mode.DIRECTION, "direction"
        self.assertEqual(brain.decide(direction, None).key, DIRS[(0, 1)])
        self.assertEqual(brain.oil, 1)

    def test_a_flask_the_list_does_not_show_is_not_in_the_pack(self) -> None:
        """The list is the game's inventory: no flask listed means none
        carried. Keeping the old count (review round 2) retried the throw 121
        times while a Poltergeist killed seed 1006 (M4 round 34)."""
        brain = Brain(GOALS["reach_dl5"])
        brain.food, brain.oil = 3, 2
        view = town_view((5, 5), (40, 40), dlvl=3, monsters={(5, 6)})
        brain.decide(command_obs(pos=(5, 5), dlvl=3, clvl=4, hp=30, mhp=40, rows={0: "You are too afraid!"}), view)
        listed = command_obs(pos=(5, 5), rows={1: " a) Ration of Food"})   # no flask listed
        listed.mode, listed.stage = Mode.ITEM, "list"
        brain.listed = True
        self.assertEqual(brain.decide(listed, None).key, 0x03)           # RUN/STOP
        self.assertEqual(brain.oil, 0)

    def test_messages_behind_more_still_count(self) -> None:
        brain = Brain(GOALS["reach_dl5"])
        brain.lamp, brain.oil = True, 2
        more = command_obs(rows={0: "Your light has gone out.", 1: "the Kobold hits you. -more-"})
        more.mode, more.stage = Mode.DISMISS, "more"
        brain.decide(more, None)
        self.assertTrue(brain.dark)
        self.assertTrue(brain.lamp)        # still worn, to be refueled (VMS, Umoria; removed until 2026-10-25)

    def test_a_more_screen_keeps_a_pending_pick(self) -> None:
        brain = Brain(GOALS["reach_dl5"])
        brain.picking = "Flask of Oil"
        more = command_obs(rows={0: "the Kobold misses you.", 1: "the Kobold hits you. -more-"})
        more.mode, more.stage = Mode.DISMISS, "more"
        self.assertEqual(brain.decide(more, None).key, KEY_SPACE)
        self.assertEqual(brain.picking, "Flask of Oil")

    def test_text_already_counted_on_a_prompt_screen_counts_once(self) -> None:
        brain = Brain(GOALS["reach_dl5"])
        view = town_view((5, 5), (40, 40), dlvl=1)
        start = brain.food
        shown = {0: "You picked up a Ration of Food."}
        prompt = command_obs(pos=(5, 5), dlvl=1, clvl=2, rows=shown)
        prompt.mode, prompt.stage = Mode.DIRECTION, "direction"
        brain.decide(prompt, None)
        brain.decide(command_obs(pos=(5, 5), dlvl=1, clvl=2, rows=shown), view)
        self.assertEqual(brain.food, start + 1)

    def test_two_pickups_in_a_row_both_count(self) -> None:
        brain = Brain(GOALS["reach_dl5"])
        view = town_view((5, 5), (40, 40), dlvl=1)
        start = brain.food
        for _ in range(2):
            brain.decide(command_obs(pos=(5, 5), dlvl=1, clvl=2, rows={0: "You picked up a Ration of Food."}), view)
        self.assertEqual(brain.food, start + 2)

    def test_throws_oil_at_an_approaching_creature(self) -> None:
        """M5a: a weak Warrior (Halfling, Elf) lost melee with DL1 Kobolds;
        2d6 thrown while one approaches is damage before contact."""
        brain = Brain(GOALS["reach_dl5"])
        brain.food, brain.oil = 3, 2
        view = town_view((5, 5), (40, 40), dlvl=1, monsters={(5, 8)})   # a Kobold three squares off
        o = command_obs(pos=(5, 5), dlvl=1, clvl=1, hp=15, mhp=15)
        self.assertEqual(brain.decide(o, view).layer, "throw")

    def test_no_oil_at_a_creature_already_adjacent_or_too_weak(self) -> None:
        """Not afraid, melee answers an adjacent creature; one the lore puts
        under OIL_WORTH_HP is not worth a flask."""
        brain = Brain(GOALS["reach_dl5"])
        brain.food, brain.oil = 3, 2
        o = command_obs(pos=(5, 5), dlvl=1, clvl=5, hp=40, mhp=40)
        self.assertNotEqual(brain.decide(o, town_view((5, 5), (40, 40), dlvl=1, monsters={(5, 6)})).layer,
                            "throw")
        weak = town_view((5, 5), (40, 40), dlvl=1)
        weak.creatures[(5, 8)] = Creature("G", 3)   # a Poltergeist's 6 HP
        self.assertNotEqual(brain.decide(o, weak).layer, "throw")

    def test_early_a_weak_melee_burns_an_adjacent_foe(self) -> None:
        """M5b round 41: early only, a character whose melee does less than a
        thrown flask throws at an adjacent creature worth one, and its lantern
        keeps one. Each at its chance to hit: a throw takes three quarters of
        the missile skill (M5b round 49), so a Priest's two Dagger blows beat
        a flask; a Battle Axe too heavy for STR 10 does not (round 44)."""
        from moria_playtest import goals
        brain = Brain(goals.for_character(GOALS["reach_dl5"], "human-priest"))
        brain.food, brain.oil, brain.lamp = 3, 2, True
        adjacent = town_view((5, 5), (40, 40), dlvl=1, monsters={(5, 6)})
        early = command_obs(pos=(5, 5), dlvl=1, clvl=1, hp=15, mhp=15)
        self.assertNotEqual(brain.decide(early, adjacent).layer, "throw")   # the Dagger
        brain.weapon = ("Battle Axe", 0)
        self.assertEqual(brain.decide(early, adjacent).layer, "throw")      # too heavy at STR 10
        later = command_obs(pos=(5, 5), dlvl=1, clvl=5, hp=40, mhp=40)
        self.assertNotEqual(brain.decide(later, adjacent).layer, "throw")   # not early
        strong = command_obs(pos=(5, 5), dlvl=1, clvl=1, hp=15, mhp=15,
                             rows={22: "ST:18  IN:11  WI:17  DX:13  CO:12  CH:16"})
        self.assertNotEqual(brain.decide(strong, adjacent).layer, "throw")  # 7.5 a turn beats a flask

    def test_lantern_reserve_is_not_thrown_unless_afraid(self) -> None:
        brain = Brain(GOALS["reach_dl5"])
        brain.food, brain.oil, brain.lamp = 3, 3, True
        view = town_view((5, 5), (40, 40), dlvl=1, monsters={(5, 8)})
        o = command_obs(pos=(5, 5), dlvl=1, clvl=5, hp=40, mhp=40)
        self.assertNotEqual(brain.decide(o, view).layer, "throw")
        brain.oil = 4
        self.assertEqual(brain.decide(o, view).layer, "throw")

    def test_stocks_flasks_to_throw_from_spare_gold(self) -> None:
        """M5a round 1: the General Store comes first, and a Half-Troll that
        spent its gold on flasks there had no Word of Recall and starved."""
        brain = Brain(GOALS["reach_dl2"])
        brain.clvl = 5                           # past the early oil-first rule (M5b)
        brain.shop_buys, brain.lamp, brain.torches, brain.oil = FOOD_PER_VISIT, True, 2, 3
        brain.clw, brain.recall = 5, 2
        self.assertIn("Flask of Oil", brain.shopping_list(100))
        brain.clw, brain.recall = 0, 0           # 5 x 20 + 2 x 190 still to buy (VMS prices, M5b round 46)
        self.assertNotIn("Flask of Oil", brain.shopping_list(450))
        self.assertIn("Flask of Oil", brain.shopping_list(900))
        self.assertNotIn("Flask of Oil", brain.shopping_list())   # gold not shown

    def test_early_no_lantern_while_the_kit_torches_last(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        brain.shop_buys, brain.clvl, brain.torches = FOOD_PER_VISIT, 1, 4
        self.assertNotIn("Brass Lantern", brain.shopping_list(100))
        brain.torches = 1
        self.assertIn("Brass Lantern", brain.shopping_list(100))
        brain.clvl, brain.torches = 5, 4
        self.assertIn("Brass Lantern", brain.shopping_list(100))

    def test_early_flasks_to_throw_come_first(self) -> None:
        """M5b round 13: 8 of 13 deaths were melee on DL1-2 with about four
        flasks thrown a character; a player buys flasks first."""
        brain = Brain(GOALS["reach_dl2"])
        brain.shop_buys, brain.lamp, brain.torches, brain.oil = FOOD_PER_VISIT, True, 2, 3
        brain.clw, brain.recall = 0, 0           # potions and scrolls still to buy
        brain.clvl = 4
        self.assertIn("Flask of Oil", brain.shopping_list(100))
        brain.oil = 13                           # the lantern's 3 and 10 to throw (M5b round 48)
        self.assertNotIn("Flask of Oil", brain.shopping_list(100))
        brain.clvl, brain.oil = 5, 3
        self.assertNotIn("Flask of Oil", brain.shopping_list(100))

    def test_oil_at_a_slow_creature_only_when_melee_is_costly(self) -> None:
        """M5a round 1: 74 flasks went at worm masses a character could walk
        away from or beat; rounds 5-9: Creeping Coins cornered and killed
        characters in melee, so a costly slow creature is shot as it creeps."""
        brain = Brain(GOALS["reach_dl5"])
        brain.food, brain.oil, brain.weapon = 3, 2, ("Broad Sword", 0)
        strong = command_obs(pos=(5, 5), dlvl=3, clvl=8, hp=80, mhp=80,
                             rows={19: "ST:18/50 DX:14", 23: "HP:80/80  MP:0/0   AC:20  AU:277"})
        view = town_view((5, 5), (40, 40), dlvl=3)
        view.creatures[(5, 8)] = Creature("w", 4)   # Blue Worm mass: slow, an easy fight
        self.assertNotEqual(brain.decide(strong, view).layer, "throw")
        weak = Brain(GOALS["reach_dl5"])
        weak.food, weak.oil = 3, 2
        coins = town_view((5, 5), (40, 40), dlvl=3)
        coins.creatures[(5, 8)] = Creature("$", 4)   # Creeping Copper Coins, for a Dagger at 30 HP
        o = command_obs(pos=(5, 5), dlvl=3, clvl=3, hp=30, mhp=30)
        self.assertEqual(weak.decide(o, coins).layer, "throw")

    def test_keeps_the_last_flask_for_the_lantern(self) -> None:
        brain = Brain(GOALS["reach_dl5"])
        brain.food, brain.oil, brain.lamp, brain.torches = 3, 1, True, 0   # no torch to fall back on
        view = town_view((5, 5), (40, 40), dlvl=3, monsters={(5, 6)})
        o = command_obs(pos=(5, 5), dlvl=3, clvl=4, hp=30, mhp=40, rows={0: "You are too afraid!"})
        self.assertNotEqual(brain.decide(o, view).layer, "throw")

    def test_spare_torches_free_the_last_flask(self) -> None:
        """M4 round 35: with torches to fall back on, the lantern's last flask
        is worth more thrown at a Poltergeist that keeps the player afraid."""
        brain = Brain(GOALS["reach_dl5"])
        brain.food, brain.oil, brain.lamp, brain.torches = 3, 1, True, 2
        view = town_view((5, 5), (40, 40), dlvl=3, monsters={(5, 6)})
        o = command_obs(pos=(5, 5), dlvl=3, clvl=4, hp=30, mhp=40, rows={0: "You are too afraid!"})
        self.assertEqual(brain.decide(o, view).layer, "throw")

    def test_afraid_of_a_fast_attacker_takes_any_stairs(self) -> None:
        """M4 round 35: afraid (no melee) of something faster that follows:
        a down staircase is a way out even before the character is ready."""
        brain = Brain(GOALS["clvl5"])
        brain.food = 3
        view = town_view((5, 5), (5, 5), dlvl=2, monsters={(6, 5)})   # standing on down stairs
        view.creatures = {(6, 5): Creature("G", 3)}
        o = command_obs(pos=(5, 5), dlvl=2, clvl=2, hp=40, mhp=40,
                        rows={0: "You are too afraid!", 1: "the Poltergeist hits you."})
        self.assertEqual(brain.decide(o, view).key, ord(">"))

    def test_fast_creatures_come_from_the_tier_data(self) -> None:
        self.assertIn("Poltergeist", knowledge.fast_creatures())
        self.assertNotIn("Kobold", knowledge.fast_creatures())
        self.assertNotIn("Yellow Jelly", knowledge.fast_creatures())   # never moves


class PingPongTest(unittest.TestCase):
    """Round 11: a frontier square that standing on did not resolve is dead."""

    def test_standing_on_a_frontier_that_reveals_nothing_moves_on(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        brain.food = 3
        view = town_view((5, 5), (40, 40), dlvl=1)
        view.types = [WALL] * (COLS * ROWS)
        for x in range(3, 12):
            view.types[5 * COLS + x] = 0x0
        view.types[4 * COLS + 5] = UNKNOWN                 # unknown corner beside the player
        view.types[5 * COLS + 12] = UNKNOWN                # real unexplored space east
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=1, clvl=3), view)
        self.assertEqual(decision.layer, "explore")        # moves on instead of a no-op
        self.assertIn((5, 5), brain.level.dead_frontier)


class AuditorTest(unittest.TestCase):
    def kinds(self, auditor: Auditor, obs: Observation, tiles) -> list[str]:
        return [f.detail for f in auditor.check(obs, bytes(tiles))]

    def test_clean_command_stop(self) -> None:
        self.assertEqual(self.kinds(Auditor(), command_obs(), floor_tiles()), [])

    def test_stack_drift(self) -> None:
        auditor = Auditor()
        auditor.check(command_obs(sp=0xF2), bytes(floor_tiles()))
        found = auditor.check(command_obs(sp=0xF1), bytes(floor_tiles()))
        self.assertEqual([f.kind for f in found], ["stack"])

    def test_hp_over_max_and_status_mismatch(self) -> None:
        obs = command_obs(hp=30, mhp=21)
        obs.rows[23] = "HP:21/21  MP:0/0"
        details = self.kinds(Auditor(), obs, floor_tiles())
        self.assertIn("HP 30 exceeds max HP 21", details)
        self.assertIn("status hp=21 but memory has 30", details)

    def test_three_digit_hp_fills_the_status_field(self) -> None:
        """M4 baseline: "HP:105/105MP:0/0" is a well-formed status line."""
        obs = command_obs(hp=105, mhp=105)
        obs.rows[23] = "HP:105/105MP:0/0   AC:4  AU:180   Full  "
        self.assertEqual(self.kinds(Auditor(), obs, floor_tiles()), [])

    def test_occupied_flag_must_match_monster_table(self) -> None:
        details = self.kinds(Auditor(), command_obs(monsters=[(11, 5)]), floor_tiles(occupied=[(11, 5)]))
        self.assertEqual(details, [])
        details = self.kinds(Auditor(), command_obs(), floor_tiles(occupied=[(11, 5)]))
        self.assertEqual(len(details), 1)
        self.assertIn("FLAG_OCCUPIED=1 at (11, 5)", details[0])

    def test_player_glyph_position(self) -> None:
        obs = command_obs()
        obs.rows[7] = " " * 40
        self.assertTrue(any("player glyph" in d for d in self.kinds(Auditor(), obs, floor_tiles())))

    def test_unknown_prompt_reported_once(self) -> None:
        auditor = Auditor()
        obs = dataclasses.replace(command_obs(), mode=Mode.UNKNOWN, stage="direction")
        self.assertEqual([f.cls for f in auditor.check(obs, None)], ["bot"])
        self.assertEqual(auditor.check(obs, None), [])


class ItemPromptExpectationTest(unittest.TestCase):
    def test_only_requested_item_prompts_are_expected(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        self.assertFalse(brain.expects_item_prompt())    # e.g. a stray "Quaff which item"
        brain.picking = "Flask of Oil"
        self.assertTrue(brain.expects_item_prompt())


class CharacterAuditTest(unittest.TestCase):
    """Review round 2: a game finding must end the character, and a stray
    item prompt must be filed (not crash) even before any auditor finding."""

    def character(self, findings):
        from moria_playtest import session as sess
        from moria_playtest.auditor import Finding

        class FakeAuditor:
            def check(self, obs, tiles):
                return [Finding(*f) for f in findings]

        filed = []
        ch = sess.Character.__new__(sess.Character)
        ch.auditor, ch.brain, ch.result = FakeAuditor(), Brain(GOALS["reach_dl2"]), sess.Result(1)
        ch.file_finding = lambda kind, cls, detail, obs, pc=None: filed.append((kind, cls, detail))
        return ch, filed

    def test_a_game_finding_ends_the_character(self) -> None:
        ch, filed = self.character([("stack", "game", "SP drift")])
        ch.audit(command_obs(), None)
        self.assertEqual(ch.result.outcome, "finding")
        self.assertEqual(filed, [("stack", "game", "SP drift")])

    def test_a_stray_item_prompt_is_filed(self) -> None:
        ch, filed = self.character([])
        o = command_obs(rows={0: "Quaff which item (a-c)?"})
        o.mode, o.stage = Mode.ITEM, "which"
        ch.audit(o, None)
        self.assertEqual(ch.result.outcome, "budget")
        self.assertEqual([f[0] for f in filed], ["unknown_prompt"])


class RunSeedsTest(unittest.TestCase):
    """The process runner reports every seed: a character that raises or a
    worker that dies becomes an ``error`` result, never a missing one (review)."""

    def test_every_seed_gets_a_result_and_unique_findings(self) -> None:
        import os
        import tempfile
        from pathlib import Path
        from moria_playtest import session as sess
        from moria_playtest.recorder import SessionLog

        stops = Path(tempfile.mkdtemp()) / "stops"

        class FakeWorker:
            def __init__(self, *args, **kwargs) -> None:
                self.seed = None

            def stop(self) -> None:   # runs in the worker process: record it in a file
                with stops.open("a") as fh:
                    fh.write(f"stop {self.seed}\n")

        class FakeCharacter:
            def __init__(self, worker, goal, seed, log) -> None:
                self.seed, self.log = seed, log
                worker.seed = seed

            def play(self):
                self.log.finding({"kind": "k", "cls": "bot", "detail": str(self.seed),
                                  "seed": self.seed, "step": 0})
                if self.seed == 3:
                    raise RuntimeError("brain bug")
                if self.seed == 5:
                    os._exit(1)   # the worker process dies without reporting
                return sess.Result(self.seed, outcome="reached")

        saved = sess.Worker, sess.Character
        sess.Worker, sess.Character = FakeWorker, FakeCharacter
        try:
            with tempfile.TemporaryDirectory() as tmp:
                log = SessionLog(Path(tmp), {"mode": "qualify"})
                results = sess.run_seeds(GOALS["reach_dl2"], list(range(1, 9)), 3, log, None, False)
                ids = [p.name for p in (Path(tmp) / "findings").glob("F*.json")]
                characters = log.summary["characters"]
        finally:
            sess.Worker, sess.Character = saved
        self.assertEqual([r.seed for r in results], list(range(1, 9)))
        self.assertEqual({r.seed: r.outcome for r in results if r.outcome != "reached"},
                         {3: "error", 5: "error"})
        self.assertEqual(len(ids), len(set(ids)))
        self.assertEqual(len(ids), 8)
        self.assertEqual(len(characters), 8)
        # The worker that raised on seed 3 is replaced, so only the error path
        # can have stopped it.
        self.assertIn("stop 3", stops.read_text().splitlines())


class PrayerTest(unittest.TestCase):
    """M5b: the cast layer through the game's own prompts (core/player_magic.s)."""

    PRIEST = {23: "HP:6/14  MP:6/6   AC:4  AU:32    Full"}

    @staticmethod
    def spell(stage: str, rows: dict[int, str]):
        o = command_obs(rows=rows)
        o.mode, o.stage = Mode.SPELL, stage
        return o

    def listed(self, brain) -> None:
        if brain.magic.wanted is None:
            brain.magic.read_list()                      # what the pray layer does first
        brain.decide(self.spell("book", {0: "Prayer book (a-a)?"}), None)
        brain.decide(self.spell("which", {0: "Pray which? (a-c, ESC)"}), None)
        brain.decide(self.spell("list", {0: "              Prayer Book",
                                         2: " a) Detect Evil                1    1",
                                         3: " b) Cure Light Wounds          2    1",
                                         4: " c) Bless                      2    1",
                                         24: "     Pray which? (a-c, esc)"}), None)

    def test_reads_the_list_then_prays_a_heal_when_hurt(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        brain.food, brain.magic.study_due = 5, False
        view = town_view((5, 5), (40, 40), dlvl=1)
        o = command_obs(pos=(5, 5), dlvl=1, clvl=1, hp=6, mhp=14, rows=self.PRIEST)
        self.assertEqual(brain.decide(o, view).reason, "read the prayer list")
        self.listed(brain)
        self.assertEqual(brain.magic.known["Cure Light Wounds"].letter, "b")
        decision = brain.decide(o, view)
        self.assertEqual((decision.layer, decision.key), ("pray", ord("P")))
        self.assertEqual(brain.decide(self.spell("book", {0: "Prayer book (a-a)?"}), None).key, ord("A"))
        self.assertEqual(brain.decide(self.spell("which", {0: "Pray which? (a-c, ESC)"}), None).key, ord("B"))

    def test_a_refused_prayer_is_not_retried_until_the_next_level(self) -> None:
        """No turn passes on a refusal: retrying would loop forever."""
        brain = Brain(GOALS["reach_dl2"])
        brain.food, brain.magic.study_due = 5, False
        self.listed(brain)
        view = town_view((5, 5), (40, 40), dlvl=1)
        o = command_obs(pos=(5, 5), dlvl=1, clvl=1, hp=6, mhp=14, rows=self.PRIEST)
        brain.decide(o, view)
        brain.decide(self.spell("book", {0: "Prayer book (a-a)?"}), None)
        brain.decide(self.spell("which", {0: "Pray which? (a-c, ESC)"}), None)
        refused = command_obs(pos=(5, 5), dlvl=1, clvl=1, hp=6, mhp=14,
                              rows={**self.PRIEST, 0: "You're not experienced enough."})
        self.assertNotEqual(brain.decide(refused, view).layer, "pray")
        self.assertIn("Cure Light Wounds", brain.magic.refused)
        brain.magic.note("Welcome to level 2.")
        self.assertNotIn("Cure Light Wounds", brain.magic.refused)

    def test_studies_after_a_level_up_when_nothing_is_close(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        brain.food = 5
        view = town_view((5, 5), (40, 40), dlvl=1)
        o = command_obs(pos=(5, 5), dlvl=1, clvl=2, hp=14, mhp=14, rows=self.PRIEST)
        self.assertEqual((brain.decide(o, view).key), ord("F"))
        self.assertEqual(brain.decide(self.spell("book", {0: "Study which book (a-a)?"}), None).key, ord("A"))
        brain.magic.note("No new spells to learn.")
        self.assertFalse(brain.magic.study_due)
        brain.magic.note("Welcome to level 3.")
        self.assertTrue(brain.magic.study_due)

    def test_heals_in_town_too(self) -> None:
        """M5b round 3: poison drained four Priests to death in town, where
        the bot never rests."""
        brain = Brain(GOALS["reach_dl2"])
        brain.food, brain.magic.study_due = 5, False
        self.listed(brain)
        o = command_obs(pos=(5, 5), dlvl=0, clvl=3, hp=6, mhp=30, rows={23: "HP:6/30  MP:6/6   AC:4  AU:32"})
        self.assertEqual(brain.decide(o, town_view((5, 5), (40, 40))).layer, "pray")

    def test_create_food_before_a_heal_when_starving(self) -> None:
        """M5b round 29: a sealed-in Dwarf Priest healed 1,166 times while it
        starved; Create Food comes first."""
        from moria_playtest.magic import Prayer
        brain = Brain(GOALS["reach_dl2"])
        brain.food, brain.magic.study_due, brain.magic.listed = 0, False, True
        brain.magic.known = {"Create Food": Prayer("f", 5, 7, "Words of Wisdom"),
                             "Cure Light Wounds": Prayer("b", 2, 1)}
        view = town_view((5, 5), (40, 40), dlvl=2)
        o = command_obs(pos=(5, 5), dlvl=2, clvl=8, hp=20, mhp=50, rows={23: "HP:20/50  MP:20/20 AC:10 AU:32"})
        self.assertEqual(brain.pray(o, view).reason, "food low: pray Create Food")
        brain.food = 5
        self.assertEqual(brain.pray(o, view).reason, "HP 20/50: pray Cure Light Wounds")

    def test_with_no_recall_the_light_reserve_covers_the_climb(self) -> None:
        """C128, 2026-11-06: a level-23 Warrior went dark on DL20 with no Word
        of Recall and died groping DL1 49,000 steps later."""
        from moria_playtest.brain import CLIMB_LIGHT, LIGHT_RESERVE
        brain = Brain(GOALS["deep"])
        brain.lamp, brain.oil, brain.torches, brain.map_scale = True, 0, 0, 1.0
        brain.last_dlvl, brain.light_left = 20, LIGHT_RESERVE + 1000
        brain.recall = 1
        self.assertFalse(brain.light_low())                   # Recall home: the flat reserve
        brain.recall = 0
        self.assertTrue(brain.light_low())                    # twenty staircases up
        brain.light_left = LIGHT_RESERVE + 20 * CLIMB_LIGHT + 1
        self.assertFalse(brain.light_low())
        # Spares count, all of them: one torch is not the climb from DL14
        # (C128, 2026-11-07: a Halfling went dark on the way up).
        from moria_playtest.brain import TORCH_TURNS
        brain.lamp, brain.torches, brain.last_dlvl, brain.light_left = False, 1, 14, 2000
        self.assertTrue(brain.light_low())
        brain.torches = 3
        self.assertFalse(brain.light_low())                   # 14,000 turns: enough
        brain.recall, brain.torches = 1, 1
        self.assertFalse(brain.light_low())                   # Recall home: spares are plenty

    def test_a_swarm_of_fast_breeders_reads_word_of_recall_at_once(self) -> None:
        """2026-11-06: Huge White Bats, Giant Fleas, Lice and Gnats killed 51
        characters, nearly all with Word of Recall unread."""
        from moria_playtest import knowledge
        knowledge.use_port("c64")                               # the catalog's creatures
        self.addCleanup(knowledge.use_port, "")
        brain = Brain(GOALS["deep"])
        brain.recall, brain.food = 1, 20
        view = town_view((5, 5), (40, 40), dlvl=20)
        fleas = {(6, 5): Creature("F", 14), (6, 6): Creature("F", 14), (4, 4): Creature("F", 14)}
        view.creatures = dict(fleas)
        o = command_obs(pos=(5, 5), dlvl=20, clvl=22, hp=200, mhp=200)
        self.assertIsNone(brain.swarm_recall(o, view))            # three: not yet
        view.creatures[(7, 7)] = Creature("F", 14)
        self.assertEqual(brain.swarm_recall(o, view).reason, "4 breeders in view: read Word of Recall")
        view.creatures = {p: Creature("w", 1) for p in [(6, 5), (6, 6), (4, 4), (7, 7)]}   # slow worm masses
        self.assertIsNone(brain.swarm_recall(o, view))
        brain.recall = 0                                          # none to read (2026-11-06: a Dwarf
        view.creatures = {**fleas, (7, 7): Creature("F", 14)}     # stood 700 steps among lice and died)
        decision = brain.swarm_recall(o, view)
        self.assertEqual((decision.key, decision.reason), (DIRS[(1, 1)], "4 breeders in view: fight through to the stairs"))
        view.pos = (40, 40)                                       # on the down staircase
        self.assertEqual(brain.swarm_recall(o, view).key, ord(">"))

    def test_lightless_with_no_way_up_known_prays_detect_doors_stairs(self) -> None:
        """2026-11-06: a level-19 Paladin with no light hopped DL3-DL4 150,000
        steps, Detect Doors/Stairs known."""
        from moria_playtest.magic import Prayer
        brain = Brain(GOALS["deep"])
        brain.food, brain.magic.study_due, brain.magic.listed = 20, False, True
        brain.magic.known = {"Detect Doors/Stairs": Prayer("g", 11, 3, "Words of Wisdom")}
        brain.dark, brain.torches, brain.lamp = True, 0, False
        view = town_view((5, 5), (5, 5), dlvl=3)                # on a down staircase, none up known
        o = command_obs(pos=(5, 5), dlvl=3, clvl=19, hp=140, mhp=140, rows={23: "HP:140/140 MP:20/20 AC:15 AU:8557"})
        self.assertEqual(brain.pray(o, view).reason, "no way out known: pray Detect Doors/Stairs")
        self.assertIsNone(brain.pray(o, view))                   # once a while, not every step

    def test_lightless_with_a_light_spell_casts_it_as_it_goes(self) -> None:
        """C64 Balrog, 2026-11-07: a level-28 Rogue with Light Area known
        groped and searched one dark DL1 168,000 steps."""
        from moria_playtest.brain import LIT_EVERY
        from moria_playtest.magic import Prayer
        brain = Brain(GOALS["deep"])
        brain.food, brain.magic.study_due, brain.magic.listed = 20, False, True
        brain.magic.known = {"Call Light": Prayer("e", 5, 2, "Beginners Handbook")}
        brain.dark, brain.torches, brain.lamp = True, 0, False
        view = town_view((5, 5), (40, 40), dlvl=1)
        o = command_obs(pos=(5, 5), dlvl=1, clvl=28, hp=150, mhp=150, rows={23: "HP:150/150 MP:20/20 AC:28 AU:300"})
        self.assertEqual(brain.pray(o, view).reason, "no light: Call Light")
        self.assertNotEqual(getattr(brain.pray(o, view), "reason", ""), "no light: Call Light")   # not on the same spot
        view.pos = (5 + LIT_EVERY, 5)
        self.assertEqual(brain.pray(o, view).reason, "no light: Call Light")

    def test_lightless_feels_its_way_to_a_known_up_staircase(self) -> None:
        brain = Brain(GOALS["deep"])
        brain.food = 20
        brain.dark, brain.torches, brain.lamp = True, 0, False
        view = town_view((5, 5), (12, 5), dlvl=3, stairs_type=0xA)
        view.types = [UNKNOWN] * (COLS * ROWS)
        view.types[5 * COLS + 5] = 0x0                          # where the player stands
        view.types[5 * COLS + 12] = 0xA                         # an up staircase, detected
        o = command_obs(pos=(5, 5), dlvl=3, clvl=19, hp=140, mhp=140, rows={23: "HP:140/140 MP:0/0 AC:15 AU:8557"})
        decision = brain.resupply(o, view)
        self.assertEqual((decision.key, decision.reason[-29:]), (DIRS[(1, 0)], "feel the way to the up stairs"))
        brain.level.felt.add((6, 5))                             # that way was a wall
        self.assertIn(brain.dark_step(view, view.stairs_up()), {(1, -1), (1, 1)})

    def test_a_move_into_the_dark_that_went_nowhere_is_a_wall(self) -> None:
        brain = Brain(GOALS["deep"])
        view = town_view((5, 5), (40, 40), dlvl=3)
        view.types[5 * COLS + 6] = UNKNOWN
        brain.last_move = ((5, 5), (6, 5))
        brain.note_bump(command_obs(pos=(5, 5), dlvl=3), view)
        self.assertEqual(brain.level.felt, {(6, 5)})

    def test_full_pack_creates_food_only_when_hungry(self) -> None:
        """C64 Balrog queue, 2026-11-06: with a full pack the ration stayed on
        the floor, and a level-18 Ranger prayed Create Food every time its
        mana came back, 2.8 million steps on DL1."""
        from moria_playtest.magic import Prayer
        brain = Brain(GOALS["reach_dl2"])
        brain.food, brain.magic.study_due, brain.magic.listed = 0, False, True
        brain.magic.known = {"Create Food": Prayer("f", 5, 7, "Words of Wisdom")}
        brain.pack_full = True
        view = town_view((5, 5), (40, 40), dlvl=2)
        o = command_obs(pos=(5, 5), dlvl=2, clvl=8, hp=50, mhp=50, rows={23: "HP:50/50  MP:20/20 AC:10 AU:32 Full"})
        self.assertIsNone(brain.pray(o, view))
        o = command_obs(pos=(5, 5), dlvl=2, clvl=8, hp=50, mhp=50, rows={23: "HP:50/50  MP:20/20 AC:10 AU:32 Hungry"})
        self.assertEqual(brain.pray(o, view).reason, "food low: pray Create Food")

    def test_created_food_is_picked_up_before_casting_again(self) -> None:
        """M7 queue, 2026-11-02: the ration Create Food leaves underfoot was
        never picked up, and a Ranger cast it again whenever its mana came
        back, the food count still 0."""
        from moria_playtest.brain import KEY_PICKUP
        from moria_playtest.magic import Prayer
        brain = Brain(GOALS["reach_dl2"])
        brain.food, brain.magic.study_due, brain.magic.listed = 0, False, True
        brain.no_food = True
        brain.magic.known = {"Create Food": Prayer("f", 5, 7, "Words of Wisdom")}
        o = command_obs(pos=(5, 5), dlvl=2, clvl=8, hp=50, mhp=50,
                        rows={0: "You create food.", 23: "HP:50/50  MP:20/20 AC:10 AU:32"})
        decision = brain.decide(o, town_view((5, 5), (40, 40), dlvl=2))
        self.assertEqual((decision.key, decision.layer), (KEY_PICKUP, "collect"))
        o = command_obs(pos=(5, 5), dlvl=2, clvl=8, hp=50, mhp=50,
                        rows={0: "You picked up a Ration of Food.", 23: "HP:50/50  MP:20/20 AC:10 AU:32"})
        brain.decide(o, town_view((5, 5), (40, 40), dlvl=2))
        self.assertEqual((brain.food, brain.no_food), (1, False))

    def test_no_heal_that_the_adjacent_creatures_outrun(self) -> None:
        """M5b round 8: Cure Light Wounds prayed over and over beside a
        creature that took more each turn, until the character died praying."""
        brain = Brain(GOALS["reach_dl2"])
        brain.food, brain.magic.study_due = 5, False
        self.listed(brain)
        view = town_view((5, 5), (40, 40), dlvl=1)
        o = command_obs(pos=(5, 5), dlvl=1, clvl=1, hp=6, mhp=14, rows=self.PRIEST)
        brain.adjacent = [Creature("k", 1)]                            # ~3 a turn: the heal wins
        self.assertEqual(brain.pray(o, view).reason, "HP 6/14: pray Cure Light Wounds")
        brain.adjacent = [Creature("k", 1), Creature("p", 0)]         # ~9 a turn: it does not
        self.assertIsNone(brain.pray(o, view))

    def test_detect_doors_when_stuck_not_on_arrival(self) -> None:
        """M5b round 7: prayed on arrival, the one Detect Doors/Stairs was
        spent before the level was explored; a Priest sealed in later
        starved for 54,000 steps."""
        from moria_playtest.brain import DETECT_EVERY
        from moria_playtest.magic import Prayer
        brain = Brain(GOALS["reach_dl2"])
        brain.food, brain.magic.study_due, brain.magic.listed = 5, False, True
        brain.magic.known = {"Detect Doors/Stairs": Prayer("g", 3, 3)}
        view = town_view((5, 5), (40, 40), dlvl=2)
        o = command_obs(pos=(5, 5), dlvl=2, clvl=5, hp=30, mhp=30, rows={23: "HP:30/30  MP:9/9   AC:4  AU:32"})
        o.step = 100
        self.assertNotEqual(brain.decide(o, view).reason, "no way out known: pray Detect Doors/Stairs")
        brain.level.since_progress = STUCK_STEPS                     # stuck now
        self.assertEqual(brain.pray(o, view).reason, "no way out known: pray Detect Doors/Stairs")
        o.step = 200
        self.assertIsNone(brain.pray(o, view))                        # not again at once
        o.step = 100 + DETECT_EVERY
        self.assertEqual(brain.pray(o, view).reason, "no way out known: pray Detect Doors/Stairs")

    def test_warriors_never_pray(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        brain.food = 5
        o = command_obs(pos=(5, 5), dlvl=1, clvl=2, hp=4, mhp=14)   # MP:0/0
        self.assertNotEqual(brain.decide(o, town_view((5, 5), (40, 40), dlvl=1)).layer, "pray")

    def test_afraid_prays_remove_fear(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        brain.food, brain.magic.study_due, brain.magic.listed = 5, False, True
        from moria_playtest.magic import Prayer
        brain.magic.known = {"Remove Fear": Prayer("d", 2, 1)}
        view = town_view((5, 5), (40, 40), dlvl=1, monsters={(6, 5)})
        o = command_obs(pos=(5, 5), dlvl=1, clvl=2, hp=14, mhp=14, rows={**self.PRIEST, 0: "You are too afraid!"})
        decision = brain.decide(o, view)
        self.assertEqual((decision.layer, decision.reason), ("pray", "afraid: pray Remove Fear"))


class BreederTest(unittest.TestCase):
    """M5b round 1: with breeding fixed, a Paladin fought multiplying White
    Worm masses on DL1 for 3,400 steps until they killed it."""

    def test_the_lore_knows_worm_masses_breed(self) -> None:
        self.assertIn(("w", 1), knowledge.breeder_kinds())
        self.assertNotIn(("k", 1), knowledge.breeder_kinds())

    def test_a_swarm_is_left_and_breeders_are_never_hunted(self) -> None:
        brain = Brain(GOALS["clvl10"])
        brain.food = 5
        o = command_obs(pos=(5, 5), dlvl=1, clvl=5, hp=40, mhp=40)
        self.assertFalse(brain.engageable(Creature("w", 1), o))
        view = town_view((5, 5), (40, 40), dlvl=1)
        view.creatures = {(9, 5): Creature("w", 1), (9, 7): Creature("w", 1)}
        brain.decide(o, view)
        self.assertFalse(brain.level.scum)                     # two: not yet a swarm
        view.creatures[(9, 9)] = Creature("w", 1)
        brain.decide(o, view)
        self.assertTrue(brain.level.scum)


class StairsEscapeTest(unittest.TestCase):
    """M5b round 4: level-1 Priests and Paladins died to DL1 Kobolds; on the
    stairs, a creature the character would lose to is a reason to leave."""

    def test_a_weak_priest_on_the_up_stairs_leaves_a_kobold(self) -> None:
        from moria_playtest import goals
        brain = Brain(goals.for_character(GOALS["clvl10"], "half-troll-priest"))
        brain.food = 5
        view = town_view((5, 5), (5, 5), dlvl=1, stairs_type=0xA)        # standing on up stairs
        view.creatures = {(7, 5): Creature("k", 1)}
        o = command_obs(pos=(5, 5), dlvl=1, clvl=1, hp=14, mhp=14)
        decision = brain.decide(o, view)
        self.assertEqual((decision.layer, decision.key), ("retreat", ord("<")))

    def test_a_strong_warrior_stays(self) -> None:
        brain = Brain(GOALS["clvl10"])
        brain.food, brain.weapon = 5, ("Broad Sword", 0)
        view = town_view((5, 5), (5, 5), dlvl=1, stairs_type=0xA)
        view.creatures = {(7, 5): Creature("k", 1)}
        o = command_obs(pos=(5, 5), dlvl=1, clvl=5, hp=60, mhp=60,
                        rows={19: "ST:18/50 DX:12", 23: "HP:60/60  MP:0/0   AC:20  AU:277"})
        self.assertNotEqual(brain.decide(o, view).key, ord("<"))


class SpellReadinessTest(unittest.TestCase):
    """M5a round 4: Elves and Gnomes reached DL2 at level 4 with 33-41 HP,
    where two Cause Light Wounds (3d8) from a Novice caster killed them."""

    def test_the_lore_knows_the_strongest_spell_by_depth(self) -> None:
        self.assertEqual(knowledge.spell_max(1), 0)
        self.assertEqual(knowledge.spell_max(2), 24)       # Novice Priest / Mage: 3d8

class FightOddsTest(unittest.TestCase):
    """M5a: whether a creature is too strong depends on the character's own
    melee, not its level alone (50 of 141 baseline deaths were nagas)."""

    @staticmethod
    def obs(hp: int, clvl: int, strength: str):
        return command_obs(hp=hp, mhp=hp, clvl=clvl, dlvl=5,
                           rows={19: f"ST:{strength} DX:12", 23: f"HP:{hp}/{hp}  MP:0/0   AC:4  AU:277"})

    def test_a_dagger_loses_to_a_green_naga_and_beats_a_kobold(self) -> None:
        brain = Brain(GOALS["reach_dl8"])
        o = self.obs(73, 7, "16")
        self.assertGreater(brain.fight_odds(Creature("n", 5), o), 1.0)   # 1d8 crush + 2d6 acid, 40 HP
        self.assertLess(brain.fight_odds(Creature("k", 1), o), 0.5)
        self.assertTrue(brain.lore_strong(Creature("n", 5), o))
        self.assertFalse(brain.lore_strong(Creature("k", 1), o))

    def test_a_better_weapon_turns_the_odds(self) -> None:
        brain = Brain(GOALS["reach_dl8"])
        o = self.obs(73, 7, "18/50")
        dagger = brain.fight_odds(Creature("n", 5), o)
        brain.weapon = ("Broad Sword", 0)
        self.assertLess(brain.fight_odds(Creature("n", 5), o), dagger)

    def test_class_and_race_set_the_melee_skill(self) -> None:
        """M5b: a Priest's melee skill is 48 + 2 a level (a Warrior's 70 + 4),
        and the race adds its own (core/tables.s); the Warrior's skill made a
        level-1 Priest take on DL1 Kobolds it lost to."""
        from moria_playtest import goals
        o = self.obs(14, 1, "15")
        warrior = Brain(goals.for_character(GOALS["clvl10"], "half-troll-warrior")).fight_odds(Creature("k", 1), o)
        priest = Brain(goals.for_character(GOALS["clvl10"], "half-troll-priest")).fight_odds(Creature("k", 1), o)
        halfling = Brain(goals.for_character(GOALS["clvl10"], "halfling-warrior")).fight_odds(Creature("k", 1), o)
        self.assertGreater(priest, warrior)
        self.assertGreater(halfling, warrior)

    def test_other_adjacent_attackers_count(self) -> None:
        """M5a round 8: a nest fought one at a time looked an easy fight each."""
        brain = Brain(GOALS["reach_dl8"])
        o = self.obs(40, 4, "16")
        alone = brain.fight_odds(Creature("k", 1), o)
        brain.adjacent = [Creature("k", 1), Creature("k", 1), Creature("k", 1)]
        self.assertGreater(brain.fight_odds(Creature("k", 1), o), 2.5 * alone)

    def test_hurt_raises_the_odds(self) -> None:
        brain = Brain(GOALS["reach_dl8"])
        self.assertGreater(brain.fight_odds(Creature("k", 1), self.obs(8, 7, "16")),
                           brain.fight_odds(Creature("k", 1), self.obs(73, 7, "16")))


class CharacterTest(unittest.TestCase):
    """M5 (§16): a goal is played by a named race and class, and its suite is
    named for it unless it is the M0-M4 Half-Troll Warrior."""

    def test_characters_and_suite_names(self) -> None:
        from moria_playtest import goals
        from moria_playtest.session import SUITES, suite_path
        self.assertEqual(goals.for_character(GOALS["clvl10"], "human-warrior").character, ("A", "A"))
        self.assertEqual(goals.for_character(GOALS["clvl10"], "half-troll-warrior"), GOALS["clvl10"])
        self.assertEqual(len([name for name in goals.CHARACTERS if name.endswith("-warrior")]), 8)
        self.assertEqual(suite_path("clvl10"), SUITES / "clvl10.json")
        self.assertEqual(suite_path("clvl10", "gnome-warrior"), SUITES / "clvl10-gnome-warrior.json")
        # §21.2: another port's suites add the port; the C64's are unchanged.
        self.assertEqual(suite_path("clvl5", port="plus4"), SUITES / "clvl5-plus4.json")
        self.assertEqual(suite_path("clvl5", "human-mage", "plus4"), SUITES / "clvl5-human-mage-plus4.json")
        self.assertEqual(suite_path("clvl5", "human-mage", "c64"), SUITES / "clvl5-human-mage.json")

    def test_a_faulting_key_is_kept_with_the_finding(self) -> None:
        """2026-11-07: the key whose press hung was never recorded, so no
        replay of a hang's keys reached it (BBC: 50,640 keys from boot)."""
        import types
        from moria_playtest.game import GameFault
        from moria_playtest.session import Character

        class Hangs:
            def press(self, key: int):   # type: ignore[no-untyped-def]
                raise GameFault("hang", "no key wait", 0x9104)

        me = types.SimpleNamespace(worker=types.SimpleNamespace(game=Hangs()), keys=[0x4E])
        with self.assertRaises(GameFault):
            Character.press(me, 0x42)   # type: ignore[arg-type]
        self.assertEqual(me.keys, [0x4E, 0x42])

    def test_a_port_with_bigger_maps_has_a_bigger_budget(self) -> None:
        """M6: the 80-column ports' 198x66 levels are 3.4 times the C64's
        80x48; their goals' budgets grow with the area (maintainer,
        2026-10-27)."""
        from moria_playtest import goals
        from moria_playtest.ports import C128, C64, CX16, PLUS4
        self.assertEqual(goals.for_port(GOALS["reach_dl5"], C64).step_budget, 20_000)
        self.assertEqual(goals.for_port(GOALS["reach_dl5"], PLUS4).step_budget, 20_000)
        self.assertEqual(goals.for_port(GOALS["reach_dl5"], C128).step_budget, 68_062)
        self.assertEqual(goals.for_port(GOALS["clvl5"], CX16).step_budget, 102_094)

    def test_a_weak_combination_has_its_own_bar(self) -> None:
        """§16.1: Halfling and Gnome Warriors are frozen at their level."""
        from moria_playtest import goals
        saved = dict(goals.CHARACTER_BARS)
        try:
            goals.CHARACTER_BARS.clear()
            goals.CHARACTER_BARS[("halfling-warrior", "reach_dl8")] = 12
            self.assertEqual(goals.for_character(GOALS["reach_dl8"], "halfling-warrior").qualify_bar, 12)
            self.assertEqual(goals.for_character(GOALS["clvl10"], "halfling-warrior").qualify_bar, 16)
            self.assertEqual(goals.for_character(GOALS["reach_dl8"], "human-warrior").qualify_bar, 16)
        finally:
            goals.CHARACTER_BARS.clear()
            goals.CHARACTER_BARS.update(saved)

    def test_pure_casters_have_a_bar_of_10(self) -> None:
        """Maintainer, 2026-10-27 (M5f): Mages and Priests qualify at 10/20
        (15/20 from 2026-10-26)."""
        from moria_playtest import goals
        for character in ("human-priest", "dwarf-priest", "human-mage", "elf-mage", "elf-priest"):
            for goal in ("clvl10", "reach_dl8"):
                self.assertEqual(goals.for_character(GOALS[goal], character).qualify_bar, 10)
        self.assertEqual(goals.for_character(GOALS["clvl10"], "half-orc-priest").qualify_bar, 10)
        # Frozen at their level (maintainer, 2026-10-27): CHARACTER_BARS decides.
        for character, goal, bar in (("gnome-mage", "clvl10", 8), ("gnome-mage", "reach_dl8", 7),
                                     ("halfling-mage", "clvl10", 8), ("halfling-mage", "reach_dl8", 5),
                                     ("gnome-priest", "reach_dl8", 5), ("gnome-priest", "clvl10", 9)):
            self.assertEqual(goals.for_character(GOALS[goal], character).qualify_bar, bar)
        self.assertEqual(goals.for_character(GOALS["clvl10"], "human-paladin").qualify_bar, 16)
        self.assertEqual(goals.for_character(GOALS["clvl10"], "human-warrior").qualify_bar, 16)

    def test_every_allowed_combination_with_its_menu_letters(self) -> None:
        """M5b: 31 race/class combinations (§12.6), class letters as the
        filtered class menu shows them."""
        import re
        from moria_playtest import goals
        from moria_playtest.launch import ROOT
        text = (ROOT / "core/tables.s").read_text().split("race_class_flags:", 1)[1]
        masks = [int(m, 2) for m in re.findall(r"\.byte\s+%([01]+)", text)[:8]]
        self.assertEqual(masks, list(goals.RACE_CLASS_FLAGS.values()))
        self.assertEqual(len(goals.CHARACTERS), 31)
        self.assertEqual(goals.CHARACTERS["human-paladin"], ("A", "F"))
        self.assertEqual(goals.CHARACTERS["half-troll-priest"], ("H", "B"))
        self.assertEqual(goals.CHARACTERS["dwarf-warrior"], ("F", "A"))

    def test_chargen_types_the_race_and_class(self) -> None:
        from moria_playtest import goals
        from moria_playtest.brain import Brain
        brain = Brain(goals.for_character(GOALS["reach_dl2"], "dwarf-warrior"))
        typed = {}
        for stage in ("race", "class"):
            o = dataclasses.replace(command_obs(), mode=Mode.CHARGEN, stage=stage)
            typed[stage] = chr(brain.decide(o, None).key)
        self.assertEqual(typed, {"race": "F", "class": "A"})


class RunSeedsLostResultTest(unittest.TestCase):
    """A result sent just before the worker dies still arrives: a Queue's put
    left it to a feeder thread that died with the worker, and a dying writer
    could hold the Queue's lock and hang every other worker."""

    def test_result_before_a_hard_exit_is_kept(self) -> None:
        import os
        import tempfile
        from pathlib import Path
        from moria_playtest import session as sess
        from moria_playtest.recorder import SessionLog

        class FakeWorker:
            def __init__(self, *args, **kwargs) -> None:
                pass

            def stop(self) -> None:
                pass

        class FakeCharacter:
            def __init__(self, worker, goal, seed, log) -> None:
                self.seed = seed

            def play(self):
                if self.seed == 2:
                    os._exit(1)   # straight after the worker sent seed 1's result
                return sess.Result(self.seed, outcome="reached", findings=["x" * 4096])

        saved = sess.Worker, sess.Character
        sess.Worker, sess.Character = FakeWorker, FakeCharacter
        try:
            with tempfile.TemporaryDirectory() as tmp:
                log = SessionLog(Path(tmp), {"mode": "qualify"})
                results = sess.run_seeds(GOALS["reach_dl2"], [1, 2], 1, log, None, False)
        finally:
            sess.Worker, sess.Character = saved
        self.assertEqual({r.seed: r.outcome for r in results}, {1: "reached", 2: "error"})


class RunSeedsParentFailureTest(unittest.TestCase):
    """Review round 4: if the parent fails, every worker still stops its
    emulator (graceful wind-down, then SIGTERM, which unwinds like an error)."""

    def test_every_worker_stops_its_emulator(self) -> None:
        import tempfile
        import time
        from pathlib import Path
        from moria_playtest import session as sess
        from moria_playtest.recorder import SessionLog

        stops = Path(tempfile.mkdtemp()) / "stops"

        class FakeWorker:
            def __init__(self, *args, **kwargs) -> None:
                with stops.open("a") as fh:
                    fh.write("start\n")

            def stop(self) -> None:
                with stops.open("a") as fh:
                    fh.write("stop\n")

        class FakeCharacter:
            def __init__(self, worker, goal, seed, log) -> None:
                self.seed = seed

            def play(self):
                time.sleep(30 if self.seed > 1 else 0.1)   # most are mid-game: SIGTERM path
                return sess.Result(self.seed, outcome="reached")

        class FailingLog(SessionLog):
            def character(self, result) -> None:
                raise RuntimeError("parent failure")

        saved = sess.Worker, sess.Character, sess.WIND_DOWN_SECONDS
        sess.Worker, sess.Character, sess.WIND_DOWN_SECONDS = FakeWorker, FakeCharacter, 0.5
        try:
            with tempfile.TemporaryDirectory() as tmp:
                log = FailingLog(Path(tmp), {"mode": "qualify"})
                with self.assertRaises(RuntimeError):
                    sess.run_seeds(GOALS["reach_dl2"], [1, 2, 3], 3, log, None, False)
        finally:
            sess.Worker, sess.Character, sess.WIND_DOWN_SECONDS = saved
        lines = stops.read_text().splitlines()
        self.assertGreater(lines.count("start"), 0)
        self.assertEqual(lines.count("stop"), lines.count("start"))


class RecorderPathTest(unittest.TestCase):
    def test_same_seed_on_two_goals_keeps_both_traces_and_snapshots(self) -> None:
        import tempfile
        from pathlib import Path
        from types import SimpleNamespace

        from moria_playtest.recorder import SessionLog
        from moria_playtest.session import Character

        names: list[str] = []
        with tempfile.TemporaryDirectory() as tmp:
            def snapshot(name: str, state: dict) -> SimpleNamespace:
                names.append(name)
                return SimpleNamespace(path=Path(tmp) / name)   # the brain is saved beside it

            worker = SimpleNamespace(worker_id=0, snapshot=snapshot)
            log = SessionLog(Path(tmp), {"mode": "regress"})
            dirs = []
            for goal in ("enter_dungeon", "reach_dl2"):
                character = Character(worker, GOALS[goal], 1009, log)
                character.take_snapshot(command_obs())
                character.log.close()
                dirs.append(character.log.dir)
            self.assertNotEqual(dirs[0], dirs[1])
            self.assertTrue(all((d / "trace.jsonl.gz").exists() for d in dirs))
        self.assertEqual(len(set(names)), 2)


class QualifyBarTest(unittest.TestCase):
    """§7.2 / §14.6 item 5: every goal works at 16/20 (the bot need not
    play every creature perfectly)."""

    def test_bars(self) -> None:
        self.assertEqual(required(GOALS["enter_dungeon"], 20), 16)
        self.assertEqual(required(GOALS["reach_dl2"], 20), 16)
        self.assertEqual(required(GOALS["reach_dl5"], 20), 16)
        self.assertEqual(required(GOALS["clvl5"], 20), 16)
        self.assertEqual(required(GOALS["clvl5"], 4), 4)    # scaled, rounded up
        self.assertEqual(required(GOALS["clvl5"], 5), 4)


class PlateauTest(unittest.TestCase):
    def test_plateau_alert_fires_once_and_never_stops_the_session(self) -> None:
        import json
        import tempfile
        from pathlib import Path
        from unittest import mock

        from moria_playtest import session
        from moria_playtest.recorder import SessionLog

        batches = iter([[session.Result(seed=i, outcome="died")] for i in range(1, 13)]
                       + [[session.Result(seed=13, outcome="reached", max_dlvl=1)]])
        with tempfile.TemporaryDirectory() as tmp:
            log = SessionLog(Path(tmp), {"mode": "session"})
            with mock.patch.object(session, "run_seeds", lambda *a, **k: next(batches)):
                results = session.session_until_reached(GOALS["enter_dungeon"], 1, 1, log, None)
            events = [json.loads(line) for line in (Path(tmp) / "events.jsonl").read_text().splitlines()]
        self.assertEqual(results[-1].outcome, "reached")
        self.assertEqual([e["kind"] for e in events], ["plateau"])


if __name__ == "__main__":
    unittest.main()


class StatRollTest(unittest.TestCase):
    """Chargen rerolls until the class's main stat and CON reach the
    race/class bars (brain.roll_good, maintainer 2026-10-25)."""

    @staticmethod
    def screen(wis: str, con: str) -> list[str]:
        rows = [""] * 25
        for i, (name, value) in enumerate((("STR", "10"), ("INT", "12"), ("WIS", wis), ("DEX", "11"),
                                           ("CON", con), ("CHR", "12"))):
            shown = value if "/" in value else f"{int(value):2d}"   # put_stat_val: right-justified
            rows[2 + i] = f"   {name}:{shown} ({shown})".ljust(40)
        return rows

    def test_human_priest_bars(self) -> None:
        from moria_playtest.brain import roll_good
        self.assertTrue(roll_good(self.screen("14", "13"), "human", "priest"))    # WIS 17, CON 13
        self.assertFalse(roll_good(self.screen("13", "17"), "human", "priest"))   # WIS 16
        self.assertFalse(roll_good(self.screen("17", "12"), "human", "priest"))   # CON 12
        self.assertTrue(roll_good(self.screen("18/20", "14"), "human", "priest"))

    def test_brain_rerolls_then_accepts_and_gives_up(self) -> None:
        from moria_playtest.brain import ROLL_LIMIT
        from moria_playtest.goals import for_character
        brain = Brain(for_character(GOALS["clvl10"], "human-priest"))
        poor = dataclasses.replace(command_obs(), mode=Mode.CHARGEN, stage="stats", rows=self.screen("10", "10"))
        good = dataclasses.replace(poor, rows=self.screen("15", "15"))
        self.assertEqual(brain.decide(poor, None).key, ord("R"))
        self.assertEqual(brain.decide(good, None).key, KEY_RETURN)
        for _ in range(ROLL_LIMIT):
            key = brain.decide(poor, None).key
        self.assertEqual(key, KEY_RETURN)   # the cap takes what is shown

    def test_every_character_can_pass(self) -> None:
        # The game's roll (core/player_create.s): d3+d4+d5+5 a stat, totals
        # 73-84; the race's adjustment is on the screen. Every race/class the
        # game allows must pass at least 1 roll in 30 on average.
        import random
        from moria_playtest.brain import roll_good
        from moria_playtest.goals import CLASSES, RACE_CLASS_FLAGS, RACE_KEYS
        race_adj, _ = knowledge.stat_adjustments()
        rng = random.Random(7)
        rolls = []
        while len(rolls) < 3000:
            base = [rng.randint(1, 3) + rng.randint(1, 4) + rng.randint(1, 5) + 5 for _ in range(6)]
            if 73 <= sum(base) <= 84:
                rolls.append(base)
        names = ("STR", "INT", "WIS", "DEX", "CON", "CHR")
        for r, race in enumerate(RACE_KEYS):
            for c, klass in enumerate(CLASSES):
                if not RACE_CLASS_FLAGS[race] >> c & 1:
                    continue
                passed = 0
                for base in rolls:
                    rows = [""] * 25
                    for i, name in enumerate(names):
                        shown = base[i] + race_adj[r][i]
                        mod = "18/50" if shown > 18 else f"{shown:2d}"
                        rows[2 + i] = f"   {name}:{base[i]:2d} ({mod})"
                    passed += roll_good(rows, race, klass)
                self.assertGreater(passed / len(rolls), 1 / 30, f"{race} {klass}")


class DepthAndFoodTest(unittest.TestCase):
    """M5b round 34: a level-9 Dwarf Priest made 191 town trips and climbed
    from DL2 93 times by the nearest stairs."""

    def test_exhausted_level_takes_the_down_stairs_when_ready(self) -> None:
        brain = prepared(Brain(GOALS["reach_dl8"]))
        brain.food = 6
        view = UnstuckTest.corridor(UnstuckTest(), 2, (10, 5), unknown_behind=True)
        view.types[5 * COLS + 4] = 0xA                       # up stairs one step west
        obs = command_obs(pos=(5, 5), dlvl=2, clvl=9, hp=60, mhp=60)
        brain.track(obs, view)
        brain.level.searches = {spot: 6 for spot in view.search_spots(set())}
        brain.level.scum = True
        decision = brain.stair_scum(obs, view)
        self.assertEqual(decision.key, DIRS[(1, 0)])        # east, to the down stairs

    def test_create_food_keeps_a_priest_from_climbing_for_food(self) -> None:
        from moria_playtest.magic import CREATE_FOOD, Prayer
        brain = Brain(GOALS["reach_dl8"])
        brain.food = 0.5
        obs = command_obs(dlvl=2, clvl=9)
        obs.rows[23] = "HP:60/60  MP:3/20   AC:12  AU:40   Hungry".ljust(40)
        self.assertTrue(brain.needs_resupply(obs))
        brain.magic.known[CREATE_FOOD] = Prayer("f", 7, 9, "Words of Wisdom")
        self.assertFalse(brain.needs_resupply(obs))          # 7 mana within 20

    def test_shallow_trips_keep_one_ration(self) -> None:
        brain = Brain(GOALS["reach_dl8"])
        brain.food = 1.5
        brain.track(command_obs(pos=(5, 5), dlvl=2, clvl=5), town_view((5, 5), (40, 40), dlvl=2))
        self.assertFalse(brain.food_low())                   # DL2: one ration will do
        brain.track(command_obs(pos=(5, 5), dlvl=3, clvl=6), town_view((5, 5), (40, 40), dlvl=3))
        self.assertTrue(brain.food_low())                    # DL3: the depth-scaled reserve (3)


class ShunTest(unittest.TestCase):
    """M5b round 42: early, a creature the lore calls too strong is not met."""

    def priest(self):
        from moria_playtest.goals import for_character
        brain = Brain(for_character(GOALS["reach_dl8"], "human-priest"))
        brain.food = 3
        return brain

    def test_from_the_stairs_a_strong_creature_in_view_is_left_behind(self) -> None:
        brain = self.priest()
        view = town_view((5, 5), (5, 5), monsters={(5, 11)}, dlvl=1, stairs_type=0xA)   # a Kobold 6 away
        o = command_obs(pos=(5, 5), dlvl=1, clvl=1, hp=12, mhp=12)
        self.assertTrue(brain.lore_strong(Creature("k", 1), o))
        decision = brain.shun(o, view)
        self.assertEqual((decision.layer, decision.key), ("retreat", ord("<")))

    def test_walks_to_stairs_nearer_than_the_creature(self) -> None:
        brain = self.priest()
        view = town_view((5, 5), (7, 5), monsters={(5, 11)}, dlvl=1, stairs_type=0xA)
        decision = brain.shun(command_obs(pos=(5, 5), dlvl=1, clvl=1, hp=12, mhp=12), view)
        self.assertEqual(decision.key, DIRS[(1, 0)])

    def test_not_past_the_early_levels_nor_when_the_creature_is_nearer(self) -> None:
        brain = self.priest()
        far_stairs = town_view((5, 5), (5, 30), monsters={(5, 8)}, dlvl=1, stairs_type=0xA)
        self.assertIsNone(brain.shun(command_obs(pos=(5, 5), dlvl=1, clvl=1, hp=12, mhp=12), far_stairs))
        on_stairs = town_view((5, 5), (5, 5), monsters={(5, 11)}, dlvl=1, stairs_type=0xA)
        self.assertIsNone(brain.shun(command_obs(pos=(5, 5), dlvl=1, clvl=5, hp=40, mhp=40), on_stairs))


class GenocideTest(unittest.TestCase):
    """Genocide's "Type?" (maintainer, 2026-11-05: answer it, don't escape
    out): the letter of the kind seen on this level that could do the most
    damage in a turn, else 'p'."""

    def test_the_most_dangerous_kind_seen_on_the_level(self) -> None:
        brain = Brain(GOALS["deep"])
        self.assertEqual(brain.genocide_key(), (ord("P"), "p"))   # nothing seen yet
        brain.level.kinds.update({"k": 6.0, "D": 40.0, "p": 12.0, "$": 90.0})   # '$' is no letter
        self.assertEqual(brain.genocide_key(), (0xC1 + 3, "D"))    # shifted: recall_key_to_screen_code
        brain.level.kinds["D"] = 0.0
        self.assertEqual(brain.genocide_key(), (ord("P"), "p"))

    def test_the_prompt_is_answered(self) -> None:
        brain = Brain(GOALS["deep"])
        brain.level.kinds["o"] = 8.0
        prompt = command_obs(rows={0: "Type?"})
        prompt.mode, prompt.stage = Mode.GENOCIDE, "type"
        decision = brain.decide(prompt, None)
        self.assertEqual((decision.key, decision.reason), (ord("O"), "genocide o"))

    def test_kinds_seen_are_remembered_by_their_worst(self) -> None:
        """creature_danger beside the character: what danger() sums."""
        kind = next(k for k, a in knowledge.attacks().items() if a and k[0].isalpha())
        brain = Brain(GOALS["deep"])
        obs = command_obs(pos=(5, 5), dlvl=3, clvl=10, hp=60, mhp=60)
        view = town_view((5, 5), (20, 10), dlvl=3)
        view.creatures = {(6, 5): Creature(*kind)}
        brain.decide(obs, view)
        self.assertGreater(brain.level.kinds[kind[0]], 0.0)
        self.assertEqual(brain.level.kinds[kind[0]], Brain.creature_danger(Creature(*kind), 1, obs))
