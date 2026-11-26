"""Unit tests for CP/M Z80 playtester integration."""

from __future__ import annotations

import os
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

import moria_playtest.brain as brain_mod
from moria_playtest import abi as abimod
from moria_playtest import knowledge, launch, magic
from moria_playtest.auditor import Auditor
from moria_playtest.brain import Brain
from moria_playtest.cpm import C128_CPM_KEYBUF, CpmC128Game, CpmGame, CpmProcess, cpm_keys
from moria_playtest.game import KEY_RUNSTOP, Mode, Observation, classify
from moria_playtest.goals import GOALS
from moria_playtest.launch import ROOT, Build
from moria_playtest.magic import Magic
from moria_playtest.ports import CPM, CPM_C128, PORTS
from moria_playtest.vice import StopInfo
from moria_playtest.tour import Tour
from moria_playtest.view import DIRS, NOTABLE_GLYPH, TERRAIN_GLYPHS, View


def _cpm_abi() -> abimod.Abi:
    labels = {
        "abi_current_overlay": 0x6A06,
        "player_data": 0x6D6B,
        "monster_table": 0x7542,
        "cr_level": 0x7793,
        "store_door_x": 0x3078,
        "store_door_y": 0x3080,
        "zp_rng_0": 0x08,
        "zp_entropy": 0x0C,
        "zp_turn_lo": 0x10,
        "zp_game_flags": 0x12,
        "zp_player_x": 0x13,
        "zp_player_y": 0x14,
        "zp_player_dlvl": 0x15,
        "zp_player_lvl": 0x16,
        "zp_player_hp_lo": 0x17,
        "zp_player_mhp_lo": 0x19,
        "zp_player_mp": 0x1B,
        "zp_player_mmp": 0x1C,
        "zp_hunger_state": 0x1D,
        "zp_mon_count": 0x1E,
        "zp_view_x": 0x20,
        "zp_view_y": 0x21,
        "zp_light_radius": 0x22,
        "zp_eff_resist": 0x40,
        "eff_resist_cold_timer": 0x41,
    }
    consts = {name: spec[1] for name, spec in {**CPM.base_consts, **CPM.consts}.items()}  # type: ignore[arg-type]
    return abimod.Abi(labels=labels, consts=consts, all_symbols={})


def _make_obs(rows: list[str] | None = None, *, ret: int = 0x4CAB, game_flags: int = 0,
              abi: abimod.Abi | None = None) -> Observation:
    padded = list(rows or []) + [""] * (25 - len(rows or []))
    zp = bytearray(256)
    zp[0x12] = game_flags
    return Observation(
        step=1, pc=0x0789, sp=0x8DFC, port01=0, ret=ret, overlay=0, zp=bytes(zp),
        player=b"\x00" * 114, monsters=b"\xff" * (32 * 12), screen=b" " * 2000, rows=padded[:25],
        abi=abi or _cpm_abi(),
    )


class CpmAbiTest(unittest.TestCase):
    def test_parse_sjasmplus_sym_and_equ(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            sym = root / "test.sym"
            sym.write_text("foo: EQU 0x00001234\nbar: EQU 0x0000ABCD\n.label k = $10\n", encoding="utf-8")
            syms = abimod.parse_vs(sym)
            self.assertEqual(syms["foo"], [0x1234])
            self.assertEqual(syms["bar"], [0xABCD])
            self.assertEqual(syms["k"], [0x10])

            inc = root / "defs.inc"
            inc.write_text(
                "; SKIP_CONST EQU 0x99\n"
                "MAP_COLS EQU 198 ; width\n"
                "GAME_FLAG_OVER EQU 0x01\n",
                encoding="utf-8",
            )
            self.assertIsNone(abimod.const_value(root, "defs.inc", "SKIP_CONST"))
            self.assertEqual(abimod.const_value(root, "defs.inc", "MAP_COLS"), 198)
            self.assertEqual(abimod.const_value(root, "defs.inc", "GAME_FLAG_OVER"), 1)

    def test_base_override_source_alias_and_zp_aliases(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "defs.inc").write_text("MAX_DUNGEON_CREATURES EQU 32\n", encoding="utf-8")
            sym = root / "main.sym"
            sym.write_text("input_get_key: EQU 0x00000789\nabi_player_x: EQU 0x00006A13\n", encoding="utf-8")
            port = SimpleNamespace(
                labels={"input_get_key": "hal/input.asm"},
                consts={"CATALOG_DUNGEON_CREATURES": ("defs.inc", 32, "MAX_DUNGEON_CREATURES")},
                base_labels={"abi_player_x": "state.inc"},
                base_consts={},
                zp_aliases=(("zp_player_x", 0x13, "abi_player_x"),),
                kernal={},
            )
            self.assertEqual(abimod.check(sym, root, port), [])  # type: ignore[arg-type]
            loaded = abimod.load(sym, root, port)  # type: ignore[arg-type]
            self.assertEqual(loaded.zp_player_x, 0x13)
            self.assertEqual(loaded.all_symbols["zp_player_x"], [0x6A13])
            self.assertEqual(loaded.CATALOG_DUNGEON_CREATURES, 32)

    def test_shipping_cpm_sym_abi_check(self) -> None:
        sym = Build.shipping(CPM).vs
        if not sym.exists():
            self.skipTest(f"{sym} not built yet")
        self.assertEqual(abimod.check(sym, ROOT, CPM), [])

    def test_cpm_player_stat_and_max_xp_consts_match_defs(self) -> None:
        _, consts = abimod.tables(CPM)
        expected = {
            "PL_STR_BASE": 21,
            "PL_STR_CUR": 27,
            "PL_CON_CUR": 31,
            "PL_MAX_XP_0": 111,
        }
        for name, value in expected.items():
            self.assertIn(name, consts)
            self.assertEqual(consts[name], (str(consts[name][0]), value))
            self.assertEqual(abimod.const_value(ROOT, "core/z80/defs.inc", name), value)
        obs = _make_obs(abi=_cpm_abi())
        player = bytearray(obs.player)
        player[111:114] = (123456).to_bytes(3, "little")
        obs = Observation(**{**obs.__dict__, "player": bytes(player)})
        self.assertEqual(obs.max_xp, 123456)


class CpmAdapterTest(unittest.TestCase):
    def test_cpm_keys_translation(self) -> None:
        self.assertEqual(cpm_keys(ord("A")), b"a")
        self.assertEqual(cpm_keys(ord("Z")), b"z")
        self.assertEqual(cpm_keys(0xC5), b"E")
        self.assertEqual(cpm_keys(0xD1), b"Q")
        self.assertEqual(cpm_keys(0x9D), b"\x1b[D")
        self.assertEqual(cpm_keys(0x1D), b"\x1b[C")
        self.assertEqual(cpm_keys(0x91), b"\x1b[A")
        self.assertEqual(cpm_keys(0x11), b"\x1b[B")
        self.assertEqual(cpm_keys(0x14), b"\x08")
        self.assertEqual(cpm_keys(0x03), b"\x1b")
        self.assertEqual(cpm_keys(ord("5")), b"5")
        self.assertEqual(cpm_keys(0x0D), b"\r")

    def test_classify_cpm_prompts_and_screens(self) -> None:
        abi = _cpm_abi()
        cmd_rows = [""] * 25
        cmd_rows[21] = "Adventurer   Human Mage                 LV: 1 DL: 0"
        self.assertEqual(classify(_make_obs(cmd_rows, abi=abi), abi, 0x4CAB), (Mode.COMMAND, "command"))

        self.assertEqual(classify(_make_obs(["You hit the kobold. --more--"], abi=abi), abi, 0x4CAB),
                         (Mode.DISMISS, "more"))
        self.assertEqual(classify(_make_obs(["", "Second row --more--"], abi=abi), abi, 0x4CAB),
                         (Mode.DISMISS, "more"))
        self.assertEqual(classify(_make_obs(["", "       /         Rest In Peace          \\"], abi=abi), abi, 0x4CAB),
                         (Mode.DEATH, "tombstone"))

        for prompt in (
            "Wear which item (a-v)? (a-c, ?-list) ",
            "Eat which item? (a-b, ?-list) ",
            "Recharge which item? (a-a, ?-list) ",
            "Which item? (a-b, ?-list) ",
            "Quaff which potion (a-v)? (a-b, ?-list) ",
        ):
            self.assertEqual(classify(_make_obs([prompt], abi=abi), abi, 0x4CAB), (Mode.ITEM, "which"), prompt)

        self.assertEqual(classify(_make_obs(["Select an item (a-v, ESC cancels):"], abi=abi), abi, 0x4CAB),
                         (Mode.ITEM, "list"))
        self.assertEqual(classify(_make_obs(["Direction?"], abi=abi), abi, 0x4CAB),
                         (Mode.DIRECTION, "direction"))
        self.assertEqual(classify(_make_obs(["Which direction? "], abi=abi), abi, 0x4CAB),
                         (Mode.DIRECTION, "direction"))
        self.assertEqual(classify(_make_obs(["Which type of monster? "], abi=abi), abi, 0x4CAB),
                         (Mode.GENOCIDE, "type"))

        self.assertEqual(classify(_make_obs(["Use which spell book? (a-b, ?-list) "], abi=abi), abi, 0x4CAB),
                         (Mode.SPELL, "book"))
        self.assertEqual(classify(_make_obs(["Use which prayer book? (a-b, ?-list) "], abi=abi), abi, 0x4CAB),
                         (Mode.SPELL, "book"))
        self.assertEqual(classify(_make_obs(["Cast which spell (a-c, ?=list, ESC)? "], abi=abi), abi, 0x4CAB),
                         (Mode.SPELL, "which"))
        self.assertEqual(classify(_make_obs(["Recite which prayer (a-d, ?=list, ESC)? "], abi=abi), abi, 0x4CAB),
                         (Mode.SPELL, "which"))
        self.assertEqual(classify(_make_obs(["Learn which spell (a-c, ?=list, ESC)? "], abi=abi), abi, 0x4CAB),
                         (Mode.SPELL, "learn_prompt"))

        modal_cast = [""] * 25
        modal_cast[1] = "     Name                         Lv    MP    Fail  Status"
        modal_cast[3] = "  a) Magic Missile               1     1     22%   Untried"
        modal_cast[22] = "  Choose letter (a-a) or ESC to cancel."
        self.assertEqual(classify(_make_obs(modal_cast, abi=abi), abi, 0x4CAB), (Mode.SPELL, "list"))

        modal_learn = list(modal_cast)
        modal_learn[3] = "  a) Detect Monsters             1     1     22%   Available"
        self.assertEqual(classify(_make_obs(modal_learn, abi=abi), abi, 0x4CAB), (Mode.SPELL, "learn"))

        store_rows = [""] * 25
        store_rows[19] = "B)uy  S)ell  Q)uit   Gold: 500"
        store_rows[21] = " Your offer? (Q=cancel)"
        self.assertEqual(classify(_make_obs(store_rows, abi=abi), abi, 0x4CAB), (Mode.STORE, "haggle"))

        for look_row in (
            "You (@) are here.",
            "You (@) are here on a staircase down.",
            "You see a Ration of Food.",
            "You see 25 gold pieces.",
            "Entrance to General Store.",
        ):
            self.assertEqual(
                classify(_make_obs([look_row], ret=0x1234, abi=abi), abi, 0x4CAB),
                (Mode.LOOK, "look"),
                look_row,
            )
        cmd_with_msg = list(cmd_rows)
        cmd_with_msg[0] = "You see a Ration of Food."
        self.assertEqual(classify(_make_obs(cmd_with_msg, abi=abi), abi, 0x4CAB), (Mode.COMMAND, "command"))

    def test_magic_cpm_modal_lv_mp_order_and_learn_prompt(self) -> None:
        m = Magic("mage")
        m.books = ["Beginners-Magick", "Magick I"]
        m.current = "Beginners-Magick"
        m.wanted = "Stinking Cloud"

        learn_prompt_obs = _make_obs(["Learn which spell (a-b, ?=list, ESC)? "])
        learn_prompt_obs.mode, learn_prompt_obs.stage = Mode.SPELL, "learn_prompt"
        self.assertEqual(m.prompt(learn_prompt_obs)[0], magic.KEY_LIST)

        list_rows = [""] * 25
        list_rows[1] = "     Name                         Lv    MP    Fail  Status"
        list_rows[3] = "  a) Stinking Cloud              3     2     30%   Untried"
        list_rows[22] = "  Choose letter (a-a) or ESC to cancel."
        list_obs = _make_obs(list_rows)
        list_obs.mode, list_obs.stage = Mode.SPELL, "list"
        key, layer, _ = m.prompt(list_obs)
        self.assertEqual((key, layer), (ord("A"), "prompt"))
        self.assertEqual(m.known["Stinking Cloud"].level, 3)
        self.assertEqual(m.known["Stinking Cloud"].mana, 2)

        learn_rows = list(list_rows)
        learn_rows[3] = "  a) Phase Door                  1     2     22%   Available"
        learn_obs = _make_obs(learn_rows)
        learn_obs.mode, learn_obs.stage = Mode.SPELL, "learn"
        self.assertEqual(m.learn(learn_obs)[0], ord("A"))

        m.study_book = "Beginners-Magick"
        m.note("You have learned the spell Phase Door.")
        self.assertIsNone(m.study_book)
        m.study_book = "Magick I"
        m.note("No learnable spells in that book.")
        self.assertIn("Magick I", m.study_done)

    def test_terrain_caret_and_catalog_enabled_for_cpm(self) -> None:
        self.assertIn("^", TERRAIN_GLYPHS)
        self.assertIsNone(NOTABLE_GLYPH.search("^"))
        self.addCleanup(knowledge.use_port, "")
        knowledge.use_port("cpm")
        self.assertTrue(knowledge.uses_catalog())

    def test_tour_legal_accepts_cpm_help_footer(self) -> None:
        def fake_obs(row0: str, mode: Mode = Mode.UNKNOWN) -> SimpleNamespace:
            return SimpleNamespace(rows=[row0] + [""] * 24, mode=mode)

        screens = [
            fake_obs("Command Reference (Page 1/2)  [L] License & Source Offer"),
            fake_obs("License & Source"),
            fake_obs("MORIA8 LICENSE NOTICE"),
            fake_obs("License & Source"),
            fake_obs("MORIA8 SOURCE OFFER"),
            fake_obs("License & Source"),
            fake_obs("Command Reference (Page 1/2)  [L] License & Source Offer"),
            fake_obs("", mode=Mode.COMMAND),
        ]
        worker = SimpleNamespace(game=SimpleNamespace(abi=SimpleNamespace(all_symbols={}), press=lambda k: screens.pop(0)))
        trip = Tour(worker, fake_obs("", mode=Mode.COMMAND))  # type: ignore[arg-type]
        trip.legal()
        self.assertEqual(trip.steps[-1], "back at the command prompt after Help")

    def test_brain_parses_cpm_equipment_pack_weights_store_articles_and_takeoff(self) -> None:
        self.addCleanup(knowledge.use_port, "")
        knowledge.use_port("cpm")
        b = Brain(GOALS["enter_dungeon"])

        eq_rows = [""] * 25
        eq_rows[2] = "  a) Wielding  : a Broad Sword (2d5) (+1,+2)                            15.0 lb"
        eq_rows[3] = "  b) Body Armor: a Leather Armor [4,+1]                                 15.0 lb"
        eq_rows[4] = "  c) Shield    : (none)"
        eq_rows[5] = "  d) Helm      : (none)"
        eq_rows[6] = "  e) Gloves    : (none)"
        eq_rows[7] = "  f) Boots     : (none)"
        eq_rows[8] = "  g) Light     : a Wooden Torch (with 4000 turns of light)               4.0 lb"
        eq_rows[9] = "  h) Ring L    : a Ring of Resist Fire                                   0.2 lb"
        eq_rows[10] = "  i) Amulet    : an Amulet of Resist Acid                                0.3 lb"
        eq_rows[11] = "  j) Ring R    : a Ring of Speed (+1)                                    0.2 lb"
        eq_rows[12] = "  k) Cloak     : (none)"
        eq_rows[13] = "  l) Secondary : a Dagger (1d4) (+0,+0)                                  1.2 lb"
        worn = b.read_equipment(eq_rows)
        self.assertEqual(
            worn,
            {
                "ICAT_ARMOR": 5,
                "ICAT_SHIELD": 0,
                "ICAT_HELM": 0,
                "ICAT_GLOVES": 0,
                "ICAT_BOOTS": 0,
                "ICAT_CLOAK": 0,
            },
        )
        b.read_weapon(eq_rows)
        self.assertEqual(b.weapon, ("Broad Sword (2d5)", 2))
        b.read_resists(eq_rows)
        self.assertEqual(b.armour_names, {"ICAT_ARMOR": "Leather Armor [4,+1]"})
        jewels = b.read_jewels(eq_rows)
        self.assertGreater(jewels["Ring"], 0)
        self.assertGreater(jewels["Ring2"], 0)
        self.assertGreater(jewels["Amulet"], 0)
        self.assertEqual(
            b.jewel_names,
            {"Ring": "Ring of Resist Fire", "Amulet": "Amulet of Resist Acid", "Ring2": "Ring of Speed (+1)"},
        )
        b.worn_listed = b.read_worn(eq_rows)
        self.assertEqual(len(b.worn_listed), 7)

        pack_rows = [
            "  a) 5 Ration of Food                                                    5.0 lb",
            "  b) a Long Bow                                                          4.0 lb",
            "  c) an Azure Potion                                                     0.4 lb",
        ]
        b.sync_counts(pack_rows, "all")
        self.assertEqual(b.food, 5)
        self.assertEqual(b.carried_weight(), 50 + 40 + 0 + 75 + 80 + 10 + 2 + 3 + 2 + 12)
        self.assertEqual(brain_mod.unknown_kind("an Azure Potion                                                     0.4 lb"), "potion")

        b.dropping = True
        drop_obs = Observation(
            0, 0x4CAB, 0x8DFE, 0, 0, 0, bytes(256), bytes(128), bytes(160), b" " * 2000,
            ["Drop which item (a-b, ?-list)?", "  a) a Ration of Food                                                   1.0 lb", "  b) a Wand of Light (3 charges)                                        1.0 lb"] + [""] * 22,
            mode=Mode.ITEM, stage="list", abi=_cpm_abi(),
        )
        drop_dec = b.drop_prompt(drop_obs)
        self.assertEqual(drop_dec.key, ord("B"))

        self.assertEqual(
            brain_mod.STORE_ITEM.match("  f) a Leather Armor [4,+1]                                              120 GP").group(2),
            "Leather Armor [4,+1]",
        )
        self.assertEqual(
            brain_mod.STORE_ITEM.match("  g) an Amulet of Wisdom (+2)                                           1200 GP").group(2),
            "Amulet of Wisdom (+2)",
        )

        b.taking_off = "Leather Armor [4,+1]"
        b.armour["ICAT_ARMOR"] = 5
        takeoff_obs = Observation(
            0, 0x4CAB, 0x8DFE, 0, 0, 0, bytes(256), bytes(128), bytes(160), b" " * 2000,
            ["Take off which item (a-c, ?-list)?", "a) a Broad Sword (2d5) (+1,+2)", "b) a Leather Armor [4,+1]"] + [""] * 22,
            mode=Mode.ITEM, stage="list", abi=_cpm_abi(),
        )
        dec = b.pick_takeoff(takeoff_obs)
        self.assertEqual(dec.key, ord("B"))
        self.assertEqual(b.armour["ICAT_ARMOR"], 0)
        self.assertNotIn("ICAT_ARMOR", b.armour_names)

    def test_cpm_rng_addr_launch_identity_and_process_runner_path(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            bdir = root / "cpm"
            bdir.mkdir()
            (bdir / "cpm_runner").write_bytes(b"ELF")
            com = bdir / "MORIA8.COM"
            dat = bdir / "MORIA8.DAT"
            sym = bdir / "main.sym"
            com.write_bytes(b"\xC9" * 10)
            dat.write_bytes(b"M8CP" + b"\x01\x01" + b"\x00" * 250)
            sym.write_text("abi_rng_seed: EQU 0x00006A08\n")
            os.utime(com, (1000, 1000))
            os.utime(dat, (900, 900))
            build = launch.Build(bdir, com, sym, port="cpm")
            with self.assertRaises(launch.StaleDisk):
                launch.check_disk(build)
            os.utime(dat, (1100, 1100))
            launch.check_disk(build)
            ident = launch.build_identity(build)
            self.assertNotEqual(ident["disk_sha256"], ident["program_sha256"])

            proc = CpmProcess(worker=0, workdir=root, disk=bdir, target=CPM)
            with mock.patch("moria_playtest.cpm.subprocess.Popen") as popen:
                popen.return_value = SimpleNamespace(stdout=SimpleNamespace(fileno=lambda: 0), stdin=None)
                with mock.patch("moria_playtest.cpm.os.set_blocking"):
                    proc.start_cpm()
                self.assertEqual(proc.args[0], str(bdir / "cpm_runner"))

        fake_game = CpmGame.__new__(CpmGame)
        fake_game.abi = SimpleNamespace(zp_rng_0=0x08, all_symbols={"zp_rng_0": (0x6A08, None)})
        self.assertEqual(fake_game.rng_addr(), 0x6A08)

    def test_cpm_look_cursor_captures_items_and_suppresses_unknown_prompt(self) -> None:
        self.addCleanup(knowledge.use_port, "")
        knowledge.use_port("cpm")
        abi = _cpm_abi()
        auditor = Auditor()
        brain = Brain(GOALS["enter_dungeon"])
        brain.food = 5

        def make_cmd_obs(step: int, row0: str = "", pos: tuple[int, int] = (5, 5)) -> Observation:
            zp = bytearray(256)
            zp[abi.zp_player_x], zp[abi.zp_player_y] = pos
            zp[abi.zp_player_dlvl] = 1
            zp[abi.zp_player_lvl] = 1
            zp[abi.zp_player_hp_lo] = 10
            zp[abi.zp_player_mhp_lo] = 10
            rows = [""] * 25
            rows[0] = row0
            rows[21] = "Adventurer   Human Mage  Search*        LV:1  DL:1"
            rows[23] = "HP: 10/10  MP: 0/0   AC: 1   AU: 0     Full"
            vrow = pos[1] + abi.hal_layout_viewport_y
            vcol = pos[0] + abi.hal_layout_viewport_x
            rows[vrow] = (" " * vcol) + "@"
            obs = Observation(
                step=step, pc=0x0789, sp=0x8DFE, port01=0, ret=0x4CAB, overlay=0,
                zp=bytes(zp), player=b"\x00" * abi.PL_STRUCT_SIZE, monsters=b"\xff" * (32 * 12),
                screen=b" " * 2000, rows=rows, abi=abi,
            )
            obs.mode, obs.stage = classify(obs, abi, 0x4CAB)
            return obs

        def make_look_obs(step: int, row0: str, pos: tuple[int, int] = (5, 5)) -> Observation:
            obs = make_cmd_obs(step, row0=row0, pos=pos)
            obs.ret = 0x5800
            obs.mode, obs.stage = classify(obs, abi, 0x4CAB)
            return obs

        types = [0] * (abi.hal_layout_map_cols * abi.hal_layout_map_rows)
        view = View(abi.hal_layout_map_cols, abi.hal_layout_map_rows, types, (5, 5), 1, {}, unknown={(7, 5): ",", (6, 6): "$"})

        obs0 = make_cmd_obs(1)
        self.assertEqual(auditor.check(obs0, None), [])
        dec0 = brain.decide(obs0, view)
        self.assertEqual(dec0.key, brain_mod.KEY_LOOK)
        self.assertEqual(brain.pending_look, ((6, 6), "$"))

        for step, row0, expected_key in (
            (2, "You (@) are here.", DIRS[(1, 1)]),
            (3, "You see 25 gold pieces.", KEY_RUNSTOP),
        ):
            lobs = make_look_obs(step, row0)
            self.assertEqual(lobs.mode, Mode.LOOK)
            self.assertEqual(auditor.check(lobs, None), [])
            self.assertEqual(brain.decide(lobs, None).key, expected_key)

        obs_mid = make_cmd_obs(4, row0="")
        view_mid = View(abi.hal_layout_map_cols, abi.hal_layout_map_rows, types, (5, 5), 1, {}, unknown={(7, 5): ",", (6, 6): "$"})
        self.assertEqual(auditor.check(obs_mid, None), [])
        dec1 = brain.decide(obs_mid, view_mid)
        self.assertEqual(brain.items_seen[(6, 6)], ("$", "gold pieces"))
        self.assertEqual(dec1.key, brain_mod.KEY_LOOK)
        self.assertEqual(brain.pending_look, ((7, 5), ","))

        for step, row0, expected_key in (
            (5, "You (@) are here.", DIRS[(1, 0)]),
            (6, "You see a stone floor.", DIRS[(1, 0)]),
            (7, "You see 5 Ration of Food.", KEY_RUNSTOP),
        ):
            lobs = make_look_obs(step, row0)
            self.assertEqual(lobs.mode, Mode.LOOK)
            self.assertEqual(auditor.check(lobs, None), [])
            self.assertEqual(brain.decide(lobs, None).key, expected_key)

        obs_done = make_cmd_obs(8, row0="")
        view_done = View(abi.hal_layout_map_cols, abi.hal_layout_map_rows, types, (5, 5), 1, {}, unknown={(7, 5): ",", (6, 6): "$"})
        self.assertEqual(auditor.check(obs_done, None), [])
        brain.decide(obs_done, view_done)
        self.assertEqual(brain.items_seen[(7, 5)], (",", "Ration of Food"))

        # Offscreen remembered glyphs must not trigger clamped Mode.LOOK targets,
        # and an offscreen pending_look inside Mode.LOOK aborts without capture.
        vw, vh = abi.hal_layout_viewport_w, abi.hal_layout_viewport_h
        off_pos = (5, vh + 4)
        off_view = View(abi.hal_layout_map_cols, abi.hal_layout_map_rows, types, (5, 5), 1, {},
                        unknown={off_pos: ","}, screen=(0, 0, vw, vh))
        self.assertIsNone(brain.look(make_cmd_obs(9, row0=""), off_view))
        brain.pending_look = (off_pos, ",")
        off_look = make_look_obs(10, "You see 25 gold pieces.")
        self.assertEqual(brain.decide(off_look, None).key, KEY_RUNSTOP)
        self.assertEqual(brain.look_message, "")
        brain.decide(make_cmd_obs(11, row0=""), off_view)
        self.assertNotIn((off_pos, ","), brain.level.identified)

    def test_cpm_c128_port_and_game_backend(self) -> None:
        self.assertIs(PORTS["cpm-c128"], CPM_C128)
        self.assertEqual(CPM_C128.source, "cpm")
        self.assertEqual(CPM_C128.platform, "cpm")
        self.assertEqual(CPM_C128.emulator, "x128")
        self.assertEqual(CPM_C128.disk, "moria8-cpm-c128.d71")
        self.assertEqual(CPM_C128.backend, "cpm_c128")
        self.assertEqual(CPM_C128.required_roms, ("PLAYTEST_CPM_C128_DISK",))

        sym = Build.shipping(CPM_C128).vs
        if sym.exists():
            self.assertEqual(abimod.check(sym, ROOT, CPM_C128), [])

        abi = _cpm_abi()
        abi.all_symbols["zp_eff_resist"] = [0x6A40]
        abi.all_symbols["eff_resist_cold_timer"] = [0x6A41]
        abi.all_symbols["abi_entropy_poll"] = [0x6A0C]
        abi.labels.update({
            "stack_canary": 0x8C00,
            "z80_state": 0x6A00,
            "abi_current_overlay": 0x6A06,
            "cpm_char_shadow": 0x8E00,
            "cpm_color_shadow": 0x9580,
            "input_get_key": 0x0784,
            "game_loop_cmd_ret": 0x4CAB,
            "game_loop_run_dir_ret": 0x4CBC,
        })

        state = bytearray(64)
        state[0x12] = 0
        screen_rows = bytearray(b" " * (80 * 24))
        line0 = b"Adventurer   Human Mage                 LV: 1 DL: 0"
        screen_rows[21 * 80:21 * 80 + len(line0)] = line0

        class FakeViceMon:
            def __init__(self) -> None:
                self.register_ids = {"PC": 3, "SP": 4, "HL": 9}
                self.stops = [
                    StopInfo(pc=0x0784, checkpoint=1, registers={3: 0x0784, 4: 0xF3DB}),
                    StopInfo(pc=0x0784, checkpoint=1, registers={3: 0x0784, 4: 0x8DFA}),
                ]
                self.writes: list[tuple[int, bytes, tuple[str, int]]] = []
                self.screenshots: list[tuple[Path, bool]] = []
                self.resumed = 0

            def bank(self, name: str) -> tuple[str, int]:
                return (name, 0)

            def checkpoint_list(self) -> list[object]:
                return []

            def checkpoint_set(self, addr: int) -> int:
                return 1

            def resume(self) -> None:
                self.resumed += 1

            def wait_stop(self, timeout: float = 60.0) -> StopInfo:
                return self.stops.pop(0)

            def mem_get(self, start: int, length: int, bank: tuple[str, int] = ("ram", 0)) -> bytes:
                if bank == ("ram00", 0) and start == C128_CPM_KEYBUF:
                    return b"\x00"
                if bank == ("ram01", 0):
                    if start == 0x8C00:
                        return b"M8SK"
                    if start == 0x6A00:
                        return bytes(state)
                    if start in (0x6A40, 0x6A41):
                        return b"\x00"
                    if start == 0x8DFA:
                        return (0x4CAB).to_bytes(2, "little")
                    if start == 0x6D6B:
                        return b"\x00" * 114
                    if start == 0x7542:
                        return b"\xff" * (32 * 12)
                    if start == 0x8E00:
                        return bytes(screen_rows)
                raise AssertionError(f"unexpected read: {bank} {start:#06x}+{length}")

            def mem_set(self, start: int, data: bytes, bank: tuple[str, int] = ("ram", 0)) -> None:
                self.writes.append((start, data, bank))

            def screenshot(self, path: Path, vdc: bool = False) -> None:
                self.screenshots.append((path, vdc))

        mon = FakeViceMon()
        with tempfile.TemporaryDirectory() as tmp:
            game = CpmC128Game(mon, abi, Path(tmp), port=CPM_C128)  # type: ignore[arg-type]
            game.arm()
            game.resolve_sites()
            obs = game.press(ord("N"))
            self.assertEqual(mon.resumed, 2)
            self.assertEqual(obs.sp, 0x8DFA)
            self.assertEqual(obs.mode, Mode.COMMAND)
            self.assertIn((C128_CPM_KEYBUF, b"n", ("ram00", 0)), mon.writes)
            self.assertTrue(game.screenshot(Path(tmp) / "shot.png"))
            self.assertEqual(mon.screenshots, [(Path(tmp) / "shot.png", True)])


if __name__ == "__main__":
    unittest.main()
