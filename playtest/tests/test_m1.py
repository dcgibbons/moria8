import dataclasses
import struct
import unittest

from moria_playtest import abi as abimod, knowledge
from moria_playtest.auditor import Auditor
from moria_playtest.brain import (FOOD_PER_VISIT, KEY_AUTOREST, KEY_REFUEL, KEY_RETURN, KEY_WEAR, LIGHT_RESERVE,
                                  DISARM_TRIES, KEY_DISARM, KEY_THROW, REFUEL_AT, RESTOCK_HOPS,
                                  Brain)
from moria_playtest.game import KEY_SPACE, Mode, Observation
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
    screen_rows = {21: f"bot Half-Troll              LV:1  DL:{dlvl}",
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


class ViewBrainTest(unittest.TestCase):
    def test_descends_when_on_stairs(self) -> None:
        brain = Brain(GOALS["enter_dungeon"])
        decision = brain.decide(command_obs(), town_view((5, 5), (5, 5)))
        self.assertEqual((decision.key, decision.layer), (ord(">"), "descend"))

    def test_walks_toward_stairs_around_a_creature(self) -> None:
        brain = Brain(GOALS["enter_dungeon"])
        decision = brain.decide(command_obs(), town_view((5, 5), (7, 5), monsters={(6, 5)}))
        self.assertIn(decision.key, (DIRS[(1, -1)], DIRS[(1, 1)]))

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
        brain.food = 3                                       # supplied: not a food test (round 25)
        view = town_view((5, 5), (40, 40), dlvl=1, monsters={(7, 5)})
        self.assertEqual(brain.decide(self.obs(), view).reason,
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
                 7: " e) Ration of Food             3 GP", 18: " B)uy  S)ell  Q)uit"}
        keys = [brain.decide(self.store_obs("menu", stock), None).key,
                brain.decide(self.store_obs("buy_which", stock), None).key,
                brain.decide(self.store_obs("buy_confirm", stock), None).key]
        self.assertEqual(keys, [ord("B"), ord("C"), ord("Y")])
        sold = {**stock, 5: " c)"}
        self.assertEqual(brain.decide(self.store_obs("menu", sold), None).key, ord("B"))
        self.assertEqual(brain.decide(self.store_obs("buy_which", sold), None).key, ord("E"))
        self.assertEqual(brain.decide(self.store_obs("menu", {3: stock[3], 18: stock[18]}), None).key, ord("Q"))
        self.assertTrue(brain.shopped)

    def test_store_message_ends_shopping(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        rows = {5: " c) Ration of Food             3 GP", 18: " B)uy  S)ell  Q)uit"}
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
        brain.food = 3                                       # supplied: not a food test (round 25)
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

    def view(self, unknown, pos=(5, 5)):
        v = town_view(pos, (60, 40), dlvl=4)
        v.unknown = dict(unknown)
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
        view = self.view({(6, 6): "$"})
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
        decision = brain.decide(self.obs(), self.view({(6, 5): "$"}))
        self.assertEqual(decision.layer, "fight")
        brain.decide(self.obs(pos=(6, 5)), self.view({}, pos=(6, 5)))   # walked onto it
        view = self.view({(6, 5): "$"})
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
        brain = Brain(GOALS["clvl5"])
        brain.food = 3
        view = town_view((5, 5), (5, 5), dlvl=2)            # on a down staircase
        view.types[5 * COLS + 20] = 0xA
        self.assertNotEqual(brain.decide(command_obs(pos=(5, 5), dlvl=2, clvl=4), view).key, ord(">"))
        self.assertEqual(brain.decide(command_obs(pos=(5, 5), dlvl=2, clvl=5), view).key, ord(">"))
        town = town_view((5, 5), (5, 5), dlvl=0)
        brain.shopped = True
        self.assertEqual(brain.decide(command_obs(pos=(5, 5), dlvl=0, clvl=1), town).key, ord(">"))

    def test_two_levels_of_margin_from_dl3(self) -> None:
        """Round 24: after round 18, the deaths sat at the new minimum (DL3
        at level 4); DL n (n >= 3) needs character level n + 2."""
        from moria_playtest.brain import ready_level
        self.assertEqual([ready_level(n) for n in range(1, 6)], [1, 3, 5, 6, 7])

    def test_underleveled_depth_goal_hunts_for_experience(self) -> None:
        brain = Brain(GOALS["reach_dl2"].__class__("reach_dl5", "", lambda o: o.dlvl >= 5, target_dlvl=5))                    # depth goal: want_xp is False
        brain.food = 3                                       # supplied: not a food test (round 25)
        view = town_view((5, 5), (40, 40), dlvl=1, monsters={(9, 5)})
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=1, clvl=1), view)
        self.assertEqual(decision.layer, "hunt")


class FoodSupplyTest(unittest.TestCase):
    """M3 round 3 (§14.3): count food as a player does; resupply before running out."""

    def test_eating_down_to_the_reserve_heads_for_town(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        brain.food = 2
        view = town_view((5, 5), (5, 2), dlvl=1, stairs_type=0xA)   # up stairs north
        o = command_obs(pos=(5, 5), dlvl=1, clvl=2)
        o.rows[0] = "You eat the Ration of Food. Delicious!".ljust(40)
        decision = brain.decide(o, view)
        self.assertEqual(brain.food, 1)
        self.assertEqual((decision.layer, decision.key), ("resupply", DIRS[(0, -1)]))

    def test_low_food_blocks_going_deeper_in_the_dungeon_but_not_from_town(self) -> None:
        brain = Brain(GOALS["reach_dl2"].__class__("reach_dl5", "", lambda o: o.dlvl >= 5, target_dlvl=5))
        brain.food = 1
        on_stairs = town_view((5, 5), (5, 5), dlvl=1)
        on_stairs.types[5 * COLS + 20] = 0xA                # a way up exists
        self.assertNotEqual(brain.decide(command_obs(pos=(5, 5), dlvl=1, clvl=2), on_stairs).key, ord(">"))
        town = town_view((5, 5), (5, 5), dlvl=0)
        brain.shopped = True
        self.assertEqual(brain.decide(command_obs(pos=(5, 5), dlvl=0, clvl=2), town).key, ord(">"))

    def test_purchases_count_and_a_refused_one_is_undone(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        menu = {5: " c) Slime Mold                 2 GP", 18: " B)uy  S)ell  Q)uit"}
        store = BrainM2Test.store_obs
        for stage in ("menu", "buy_which", "buy_confirm"):
            brain.decide(store(BrainM2Test(), stage, menu), None)
        self.assertEqual(brain.food, 2)
        brain.decide(store(BrainM2Test(), "message", {**menu, 22: " You cannot afford that."}), None)
        self.assertEqual(brain.food, 1)


class LightTest(unittest.TestCase):
    """M3 round 13 (§14.3): a lantern and oil, so the light never goes out."""

    STOCK = {3: " a) Iron Spike                 1 GP", 4: " b) Flask of Oil (250 turns)   12 GP",
             13: " k) Brass Lantern (250 turns)  24 GP", 16: " Gold: 265", 18: " B)uy  S)ell  Q)uit"}

    def store(self, brain, stage, rows):
        return brain.decide(BrainM2Test.store_obs(BrainM2Test(), stage, rows), None).key

    def test_buys_a_lantern_at_the_asking_price_then_oil(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        brain.shop_buys = FOOD_PER_VISIT
        self.assertEqual(self.store(brain, "menu", self.STOCK), ord("B"))
        self.assertEqual(self.store(brain, "buy_which", self.STOCK), ord("K"))
        haggle = {**self.STOCK, 20: " Asks 24 gp.", 21: " Your offer? (Q=cancel)"}
        self.assertEqual([self.store(brain, "haggle", haggle) for _ in range(3)],
                         [ord("2"), ord("4"), KEY_RETURN])
        self.assertTrue(brain.lamp_packed)
        sold = {**self.STOCK, 13: " k)", 16: " Gold: 241"}
        self.assertEqual(self.store(brain, "menu", sold), ord("B"))
        self.assertEqual(self.store(brain, "buy_which", sold), ord("B"))

    def test_skips_what_it_cannot_afford(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        brain.shop_buys = FOOD_PER_VISIT
        self.assertEqual(self.store(brain, "menu", {**self.STOCK, 16: " Gold: 20"}), ord("Q"))

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
        brain.shop_buys = FOOD_PER_VISIT
        stock = {**self.STOCK, 13: " k) Wooden Torch                2 GP"}
        self.assertEqual(self.store(brain, "menu", stock), ord("B"))
        self.assertEqual(self.store(brain, "buy_which", stock), ord("K"))
        self.assertEqual(self.store(brain, "buy_confirm", stock), ord("Y"))
        self.assertEqual(brain.torches, 1)

    def test_refuels_before_it_burns_out_and_heads_for_town_without_oil(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        brain.lamp, brain.oil, brain.food, brain.light_left = True, 1, 3, REFUEL_AT
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
        brain.track(command_obs(pos=(5, 5), dlvl=3, clvl=5), view)   # ready for DL3 (round 24)
        brain.level.searches = {spot: 6 for spot in view.search_spots(set())}
        brain.level.scum = True
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=3, clvl=5), view)
        self.assertEqual((decision.layer, decision.key), ("stair-scum", DIRS[(1, 0)]))

    def test_an_empty_store_pauses_resupply_and_allows_going_deeper(self) -> None:
        brain = Brain(GOALS["reach_dl2"].__class__("reach_dl5", "", lambda o: o.dlvl >= 5, target_dlvl=5))
        brain.food = 1
        brain.hops = RESTOCK_HOPS                            # round 15: restock hops used up
        o = BrainM2Test.store_obs(BrainM2Test(), "menu", {3: " a) Iron Spike                 1 GP",
                                                          18: " B)uy  S)ell  Q)uit"})
        self.assertEqual(brain.decide(o, None).key, ord("Q"))
        view = town_view((5, 5), (5, 5), dlvl=1)            # on a down staircase
        view.types[5 * COLS + 20] = 0xA                      # up stairs known
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=1, clvl=3), view)   # ready for DL2 (round 18)
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
        self.assertTrue(Brain.sealed(self.sealed_room()))
        open_view = self.sealed_room()
        open_view.types[5 * COLS + 8] = 0xA                  # an up staircase by the room
        self.assertFalse(Brain.sealed(open_view))

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

    def test_paths_keep_away_from_a_jelly(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        view = town_view((5, 5), (9, 5), dlvl=1)
        view.creatures = {(7, 5): Creature("J", 3)}
        brain.decide(command_obs(pos=(5, 5), dlvl=1, clvl=3), view)    # sets hazards
        step = view.step_toward({(9, 5)}, avoid_monsters=True)
        self.assertNotIn((5 + step[0], 5 + step[1]), {(6, 4), (6, 5), (6, 6)})


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

    def room(self, stairs):
        view = town_view((5, 5), stairs, dlvl=2, monsters={(9, 5)}, stairs_type=0xA)
        return view

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
        brain.food = 3
        o = command_obs(pos=(5, 5), dlvl=2, clvl=4, hp=30, mhp=57, rows={0: "the Novice Priest casts a spell."})
        decision = brain.decide(o, self.room((5, 40)))
        self.assertEqual((decision.layer, decision.key), ("hunt", DIRS[(1, 0)]))


class RestockHopTest(unittest.TestCase):
    """M3 round 15: stores restock on every return to town, so with no food
    for sale a player hops down to DL1 and straight back up."""

    MENU = {3: " a) Iron Spike                 1 GP", 16: " Gold: 200", 18: " B)uy  S)ell  Q)uit"}

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
        brain.light_left = 0
        menu = {**self.MENU, 4: " b) Wooden Torch (134 turns)   2 GP", 16: " Gold: 200"}
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
        brain.decide(command_obs(pos=(5, 5), dlvl=2, clvl=3), self.corridor({(8, 5): Creature("e", 1)}))
        view = self.corridor({})
        view.pos = (4, 5)
        decision = brain.decide(command_obs(pos=(4, 5), dlvl=2, clvl=3), view)
        self.assertNotEqual(decision.key, DIRS[(1, 0)])      # not back toward the eye

    def test_it_is_forgotten_when_the_player_stands_next_to_an_empty_spot(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        brain.decide(command_obs(pos=(5, 5), dlvl=2, clvl=3), self.corridor({(8, 5): Creature("e", 1)}))
        view = self.corridor({})
        view.pos = (7, 5)
        brain.decide(command_obs(pos=(7, 5), dlvl=2, clvl=3), view)
        self.assertEqual(brain.level.stationary, {})

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
        o = command_obs(pos=(5, 5), dlvl=3, clvl=3, hp=20, mhp=40, rows={0: "the Poltergeist hits you."})
        self.assertEqual(brain.decide(o, view).layer, "fight")
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

    def test_no_searching_while_something_unseen_attacks(self) -> None:
        brain = Brain(GOALS["reach_dl5"])
        brain.food = 3
        view = town_view((7, 5), (40, 40), dlvl=3)
        view.types = [WALL] * (COLS * ROWS)
        for x in range(3, 8):
            view.types[5 * COLS + x] = 0x0                 # a dead-end corridor ...
        view.types[5 * COLS + 9] = UNKNOWN                 # ... with unexplored space past its end
        view.types[5 * COLS + 3] = 0xA
        o = command_obs(pos=(7, 5), dlvl=3, clvl=4, hp=40, mhp=40)
        self.assertEqual(brain.decide(o, view).layer, "search")   # unattacked: search here
        brain = Brain(GOALS["reach_dl5"])
        brain.food = 3
        o = command_obs(pos=(7, 5), dlvl=3, clvl=4, hp=40, mhp=40, rows={0: "the Poltergeist hits you."})
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

    def test_a_cancelled_throw_keeps_the_flask_count(self) -> None:
        brain = Brain(GOALS["reach_dl5"])
        brain.food, brain.oil = 3, 2
        view = town_view((5, 5), (40, 40), dlvl=3, monsters={(5, 6)})
        brain.decide(command_obs(pos=(5, 5), dlvl=3, clvl=4, hp=30, mhp=40, rows={0: "You are too afraid!"}), view)
        listed = command_obs(pos=(5, 5), rows={1: " a) Ration of Food"})   # no flask listed
        listed.mode, listed.stage = Mode.ITEM, "list"
        brain.listed = True
        self.assertEqual(brain.decide(listed, None).key, 0x03)           # RUN/STOP
        self.assertEqual(brain.oil, 2)

    def test_messages_behind_more_still_count(self) -> None:
        brain = Brain(GOALS["reach_dl5"])
        brain.lamp, brain.oil = True, 2
        more = command_obs(rows={0: "Your light has gone out.", 1: "the Kobold hits you. -more-"})
        more.mode, more.stage = Mode.DISMISS, "more"
        brain.decide(more, None)
        self.assertTrue(brain.dark)
        self.assertFalse(brain.lamp)

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

    def test_keeps_the_last_flask_for_the_lantern(self) -> None:
        brain = Brain(GOALS["reach_dl5"])
        brain.food, brain.oil, brain.lamp = 3, 1, True
        view = town_view((5, 5), (40, 40), dlvl=3, monsters={(5, 6)})
        o = command_obs(pos=(5, 5), dlvl=3, clvl=4, hp=30, mhp=40, rows={0: "You are too afraid!"})
        self.assertNotEqual(brain.decide(o, view).layer, "throw")

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
        def snapshot(name: str, state: dict) -> SimpleNamespace:
            names.append(name)
            return SimpleNamespace(path=Path(name))

        worker = SimpleNamespace(worker_id=0, snapshot=snapshot)
        with tempfile.TemporaryDirectory() as tmp:
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
