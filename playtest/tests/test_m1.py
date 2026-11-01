import dataclasses
import struct
import unittest

from moria_playtest import abi as abimod, knowledge
from moria_playtest.auditor import Auditor
from moria_playtest.brain import (HUNT_HP, KEY_BASH, STUCK_STEPS, FOOD_MAX, FOOD_PER_VISIT, KEY_AUTOREST, KEY_REFUEL, KEY_RETURN, KEY_SEARCH, KEY_WEAR,
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
        brain = Brain(GOALS["reach_dl8"])
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
        brain.food = 3                                       # supplied: not a food test (round 25)
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

    def test_store_buys_from_a_stack(self) -> None:
        # A store stack shows its count first, as the pack does (stores
        # stack since 2026-10-25, Umoria storeCarryItem).
        brain = Brain(GOALS["reach_dl2"])
        stock = {5: " c) 5 Ration of Food           3 GP", 18: " B)uy  S)ell  Q)uit"}
        self.assertEqual(brain.decide(self.store_obs("menu", stock), None).key, ord("B"))
        self.assertEqual(brain.decide(self.store_obs("buy_which", stock), None).key, ord("C"))

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
        brain = Brain(GOALS["clvl5"])
        brain.food = 3
        view = town_view((5, 5), (5, 5), dlvl=2)            # on a down staircase
        view.types[5 * COLS + 20] = 0xA
        # HP for two DL3 spells (M5a SpellReadinessTest), so the level decides.
        self.assertNotEqual(brain.decide(command_obs(pos=(5, 5), dlvl=2, clvl=4, hp=60, mhp=60), view).key, ord(">"))
        self.assertEqual(brain.decide(command_obs(pos=(5, 5), dlvl=2, clvl=5, hp=60, mhp=60), view).key, ord(">"))
        town = town_view((5, 5), (5, 5), dlvl=0)
        brain.shopped = True
        self.assertEqual(brain.decide(command_obs(pos=(5, 5), dlvl=0, clvl=1), town).key, ord(">"))

    def test_two_levels_of_margin_from_dl3(self) -> None:
        """Round 24: after round 18, the deaths sat at the new minimum (DL3
        at level 4); DL n (n >= 3) needs character level n + 2."""
        from moria_playtest.brain import ready_level
        self.assertEqual([ready_level(n) for n in range(1, 6)], [1, 3, 5, 6, 7])
        self.assertEqual([ready_level(n, 0) for n in range(1, 6)], [1, 2, 3, 4, 5])   # depth goals

    def test_underleveled_depth_goal_hunts_for_experience(self) -> None:
        brain = Brain(GOALS["reach_dl2"].__class__("reach_dl5", "", lambda o: o.dlvl >= 5, target_dlvl=5))                    # depth goal: want_xp is False
        brain.food = 3                                       # supplied: not a food test (round 25)
        view = town_view((5, 5), (40, 40), dlvl=1, monsters={(9, 5)})
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=1, clvl=1, hp=40, mhp=40), view)   # sturdy (M5b)
        self.assertEqual(decision.layer, "hunt")


class ArrivalClimbTest(unittest.TestCase):
    """M5b round 20: a crowd escape took a level-3 Paladin down to DL2,
    where it stayed and died to a Novice Priest (seed 1019)."""

    def test_climbs_back_at_once_from_a_depth_it_is_not_ready_for(self) -> None:
        brain = Brain(GOALS["reach_dl8"])                      # DL2 wants level 4 (margin 3)
        brain.food, brain.recall, brain.torches, brain.oil = 6, 2, 2, 3
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
        self.assertEqual(brain.decide(command_obs(pos=(5, 5), dlvl=0, clvl=2), town).key, ord(">"))

    def test_purchases_count_and_a_refused_one_is_undone(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        brain.food = 1                                      # one ration carried
        menu = {5: " c) Slime Mold                 2 GP", 18: " B)uy  S)ell  Q)uit"}
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
             13: " k) Brass Lantern (250 turns)  24 GP", 16: " Gold: 265", 18: " B)uy  S)ell  Q)uit"}

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
        sold = {**self.STOCK, 13: " k)", 16: " Gold: 241"}
        self.assertEqual(self.store(brain, "menu", sold), ord("B"))
        self.assertEqual(self.store(brain, "buy_which", sold), ord("B"))

    def test_skips_what_it_cannot_afford(self) -> None:
        brain = Brain(GOALS["reach_dl2"])
        brain.shop_buys = FOOD_PER_VISIT
        # 10 gp: neither the lantern (24) nor oil (12, wanted since M4) is affordable.
        self.assertEqual(self.store(brain, "menu", {**self.STOCK, 16: " Gold: 10"}), ord("Q"))

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

    def test_a_fragile_priest_explores_near_the_stairs(self) -> None:
        # M5 regression: the 9-HP Gnome Priest's clvl10 was 10/20 with the
        # tether and 3/20 without; the Mages lost runs to it (rounds 17-18).
        from moria_playtest import goals
        def corridor(unknown_x):
            types = [WALL] * (COLS * ROWS)
            for x in range(2, 40):
                types[5 * COLS + x] = 0x0
            types[5 * COLS + 2] = 0xA                      # up stairs at the corridor's west end
            types[5 * COLS + unknown_x] = UNKNOWN
            return View(COLS, ROWS, types, (5, 5), 1, {})
        o = command_obs(pos=(5, 5), dlvl=1, clvl=1, hp=9, mhp=9)
        priest = lambda: Brain(goals.for_character(GOALS["clvl10"], "gnome-priest"))
        self.assertEqual(priest().explore(o, corridor(30)).layer, "stair-scum")   # 28 squares out: leave
        self.assertEqual(priest().explore(o, corridor(9)).layer, "explore")       # 7 squares: explore it
        mage = Brain(goals.for_character(GOALS["clvl10"], "gnome-mage"))
        self.assertEqual(mage.explore(command_obs(pos=(5, 5), dlvl=1, clvl=1, hp=7, mhp=7), corridor(30)).layer,
                         "explore")                                                 # not a Mage
        grown = command_obs(pos=(5, 5), dlvl=1, clvl=3, hp=14, mhp=14)
        self.assertEqual(priest().explore(grown, corridor(30)).layer, "explore")  # TETHER_LEVEL reached

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
        brain.track(command_obs(pos=(5, 5), dlvl=3, clvl=5), view)   # ready for DL3 (round 24)
        brain.level.searches = {spot: 6 for spot in view.search_spots(set())}
        brain.level.scum = True
        decision = brain.decide(command_obs(pos=(5, 5), dlvl=3, clvl=5), view)
        self.assertEqual((decision.layer, decision.key), ("stair-scum", DIRS[(1, 0)]))

    def test_an_empty_store_pauses_resupply_and_allows_going_deeper(self) -> None:
        brain = Brain(GOALS["reach_dl2"].__class__("reach_dl5", "", lambda o: o.dlvl >= 5, target_dlvl=5))
        brain.food = 0.5                                     # under the shallow reserve (M5b round 35)
        brain.hops = RESTOCK_HOPS                            # round 15: restock hops used up
        o = BrainM2Test.store_obs(BrainM2Test(), "menu", {3: " a) Iron Spike                 1 GP",
                                                          18: " B)uy  S)ell  Q)uit"})
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
        brain = Brain(GOALS["reach_dl2"])
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
        away = town_view((3, 5), (40, 40), dlvl=4)                     # out of reach: drink
        away.creatures = {(6, 5): Creature("$", 4)}
        self.assertEqual(brain.decide(command_obs(pos=(3, 5), dlvl=4, clvl=7, hp=14, mhp=72), away).layer,
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
        brain = Brain(GOALS["reach_dl2"])
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
        brain = Brain(GOALS["reach_dl2"])
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
        listed = command_obs(pos=(5, 5), rows={1: " a) Ration of Food", 2: " b) Potion of Cure Light Wounds"})
        listed.mode, listed.stage = Mode.ITEM, "list"
        self.assertEqual(brain.decide(listed, None).key, ord("B"))
        self.assertEqual(brain.clw, 1)


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
        rows = {0: "Store", 16: f" Gold: {gold}", 18: " B)uy  S)ell  Q)uit"}
        rows.update({3 + i: f" {chr(97 + i)}) {name:<26}{price:>4} GP" for i, (name, price) in enumerate(items)})
        o = BrainM2Test.store_obs(BrainM2Test(), "menu", rows)
        o.rows[22] = "ST:18  IN: 6  WI:11  DX:12  CO:14  CH: 6"
        return o

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
        brain.decide(command_obs(pos=(5, 5), dlvl=2, clvl=7, hp=30, mhp=30,
                                 rows={0: "You feel poisoned.", 23: "HP:30/30  MP:20/20 AC:10 AU:32"}), town_view((5, 5), (30, 30), dlvl=2))
        self.assertTrue(brain.poisoned)
        self.assertEqual(brain.pray(o, town_view((5, 5), (30, 30), dlvl=2)).reason, "poisoned: pray Cure Poison")
        self.assertTrue(brain.can_phase(o))                                          # Teleport Self is a way out
        # Books: a level-3 Mage wants Magick I from the Magic Shop.
        self.assertEqual(m.book_of("Spellbook Magick II"), "Magick II")
        self.assertEqual(m.book_of("Spellbook Magick I"), "Magick I")
        fresh = Brain(goals_for("elf-mage"))
        self.assertIn("Beginners-Magick", fresh.books_owned)
        self.assertEqual(fresh.book_wanted(command_obs(clvl=3)), "Magick I")
        self.assertIsNone(fresh.book_wanted(command_obs(clvl=2)))
        fresh.book_next, fresh.at_store = "Magick I", 5
        self.assertEqual(fresh.shopping_list(), ["Spellbook Magick I"])
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
        o = command_obs(rows={0: "Inventory", 2: "a) Short Bow", 3: "b) 12 Arrow", 4: "c) Bolt", 5: "d) Iron Shot"})
        o.mode, o.stage = Mode.ITEM, "list"
        self.assertEqual(brain.decide(o, None).reason, "drop Iron Shot")


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
        brain.food = 3
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
        brain.light_left, brain.torches = 0, 0              # out of light, no spare torch
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
        self.assertIsNone(brain.clear_way(o, coming))

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
        brain = Brain(GOALS["reach_dl8"])
        brain.food = 6
        view = UnstuckTest.corridor(UnstuckTest(), 2, (10, 5), unknown_behind=True)
        view.types[5 * COLS + 4] = 0xA                       # up stairs one step west
        obs = command_obs(pos=(5, 5), dlvl=2, clvl=9)
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
