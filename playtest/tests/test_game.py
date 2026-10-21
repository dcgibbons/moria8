import struct
import tempfile
import unittest
from pathlib import Path

from moria_playtest import abi as abimod
from moria_playtest import nav
from moria_playtest.game import (Mode, Observation, classify, derive_rng, find_jsr,
                                 snapshot_cpu_clock)
from moria_playtest.screen import decode_rows, screen_code_to_char

ABI = abimod.Abi(labels={"zp_player_x": 0x2B, "zp_player_y": 0x2C, "zp_player_hp_lo": 0x2D,
                         "zp_player_mhp_lo": 0x2F, "zp_player_lvl": 0x33,
                         "zp_player_dlvl": 0x34, "zp_game_flags": 0x43, "zp_rng_0": 0x1A},
                 consts={name: value for name, (_, value) in abimod.CONSTS.items()},
                 all_symbols={})
COMMAND_RET = 0x1181


def screen_bytes(rows: dict[int, str]) -> bytes:
    data = bytearray(b" " * 1000)
    for row, text in rows.items():
        for col, ch in enumerate(text):
            code = ord(ch)
            if "a" <= ch <= "z":
                code = ord(ch) - ord("a") + 1
            elif ch == "@":
                code = 0x00
            data[row * 40 + col] = code
    return bytes(data)


def obs(rows: dict[int, str], ret: int = 0, flags: int = 0, hp: int = 21) -> Observation:
    zp = bytearray(256)
    zp[0x43] = flags
    zp[0x2D:0x2F] = struct.pack("<h", hp)
    screen = screen_bytes(rows)
    return Observation(1, 0x10B9, 0xF2, 0x36, ret, 0, bytes(zp), bytes(111), bytes(384),
                       screen, decode_rows(screen), abi=ABI)


STATUS = {21: "bot Half-Troll              LV:1  DL:0"}


class ClassifyTest(unittest.TestCase):
    def mode(self, o: Observation, prompts=None) -> tuple[Mode, str]:
        return classify(o, ABI, COMMAND_RET, prompts)

    def test_command_needs_resident_return_and_status(self) -> None:
        self.assertEqual(self.mode(obs(STATUS, ret=COMMAND_RET)), (Mode.COMMAND, "command"))
        self.assertEqual(self.mode(obs({}, ret=COMMAND_RET))[0], Mode.UNKNOWN)

    def test_more_and_any_key(self) -> None:
        self.assertEqual(self.mode(obs({0: "The Jackal hits you. -more-", **STATUS}, ret=0x2070)),
                         (Mode.DISMISS, "more"))
        self.assertEqual(self.mode(obs({18: "         Press any key"})), (Mode.DISMISS, "anykey"))

    def test_store_stages(self) -> None:
        menu = {0: " General Store", 5: " c) Ration of Food             3 GP", 18: " B)uy  S)ell  Q)uit"}
        self.assertEqual(self.mode(obs(menu)), (Mode.STORE, "menu"))
        self.assertEqual(self.mode(obs({**menu, 20: " Buy which item? (a-l)"})), (Mode.STORE, "buy_which"))
        self.assertEqual(self.mode(obs({**menu, 21: " Price: 3 gp. Buy? (Y/N)"})), (Mode.STORE, "buy_confirm"))
        self.assertEqual(self.mode(obs({**menu, 22: " Your pack is full."})), (Mode.STORE, "message"))
        self.assertEqual(self.mode(obs({**menu, 21: " Your offer? (Q=cancel)"})), (Mode.STORE, "haggle"))

    def test_chargen_stages(self) -> None:
        self.assertEqual(self.mode(obs({18: " !     N)ew  L)oad  D)isk Setup       !"})),
                         (Mode.CHARGEN, "title"))
        self.assertEqual(self.mode(obs({0: "   Choose your race"})), (Mode.CHARGEN, "race"))
        self.assertEqual(self.mode(obs({0: "   Character Info", 18: "Press any key"})),
                         (Mode.DISMISS, "info"))

    def test_death_flow(self) -> None:
        self.assertEqual(self.mode(obs({5: "* You have died *"})), (Mode.DEATH, "tombstone"))
        self.assertEqual(self.mode(obs({0: "    Disk Setup"}, flags=0x01)), (Mode.DEATH, "disk_setup"))
        self.assertEqual(self.mode(obs({0: "    Disk Setup"})), (Mode.UNKNOWN, ""))
        self.assertEqual(self.mode(obs({}, flags=0x01)), (Mode.DEATH, "other"))

    def test_unknown_gets_resident_label(self) -> None:
        self.assertEqual(self.mode(obs({0: "Direction?"}, ret=0x39F7), {0x39F7: "direction"}),
                         (Mode.DIRECTION, "direction"))
        self.assertEqual(self.mode(obs({}, ret=0x1195), {0x1195: "run_direction"}),
                         (Mode.UNKNOWN, "run_direction"))

    def test_hp_is_signed(self) -> None:
        self.assertEqual(obs({}, hp=-3).hp, -3)


class HelpersTest(unittest.TestCase):
    def test_derive_rng_is_deterministic_and_nonzero(self) -> None:
        self.assertEqual(derive_rng(5, 0), derive_rng(5, 0))
        self.assertNotEqual(derive_rng(5, 0), derive_rng(5, 1))
        self.assertTrue(any(derive_rng(5, 0)))

    def test_find_jsr(self) -> None:
        code = bytes([0xA9, 0x01, 0x20, 0xB9, 0x10, 0x60])
        self.assertEqual(find_jsr(code, 0x1178, 0x10B9), 0x1178 + 5)
        with self.assertRaises(RuntimeError):
            find_jsr(code, 0x1178, 0x1241)

    def test_snapshot_cpu_clock(self) -> None:
        module = b"MAINCPU" + bytes(9) + bytes([1, 4]) + struct.pack("<I", 125) + struct.pack("<Q", 286899223)
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "s.vsf"
            path.write_bytes(b"VICE Snapshot File\x1a" + bytes(20) + module + bytes(16))
            self.assertEqual(snapshot_cpu_clock(path), 286899223)

    def test_screen_codes(self) -> None:
        self.assertEqual("".join(screen_code_to_char(c) for c in (0x00, 0x01, 0x41, 0x3E, 0x81)), "@aA>a")

    def test_first_step_avoids_town_store_doors(self) -> None:
        cols, rows = 5, 3
        tiles = bytearray([0x10] * 15)
        for x in range(5):
            tiles[1 * cols + x] = 0x00
        tiles[1 * cols + 2] = 0x70   # open door: a store entrance in town
        tiles[0 * cols + 2] = 0x00
        tiles[0 * cols + 1] = 0x00
        tiles[0 * cols + 3] = 0x00
        tiles[1 * cols + 4] = 0x90
        def walk(in_town: bool) -> list[tuple[int, int]]:
            pos, path = (0, 1), []
            while pos != (4, 1) and len(path) < 10:
                step = nav.first_step(bytes(tiles), cols, rows, pos, {(4, 1)}, in_town=in_town)
                assert step is not None
                pos = (pos[0] + step[0], pos[1] + step[1])
                path.append(pos)
            return path

        town = walk(True)
        self.assertEqual(town[-1], (4, 1))
        self.assertNotIn((2, 1), town)
        self.assertEqual(len(walk(False)), 4)


class AbiTableTest(unittest.TestCase):
    def test_const_parsing(self) -> None:
        self.assertEqual(abimod.parse_value("$c000"), 0xC000)
        self.assertEqual(abimod.parse_value("%101"), 5)
        self.assertEqual(abimod.parse_value("56"), 56)

    @unittest.skipUnless(abimod.C64_VS.exists(), "C64 build symbols not present")
    def test_table_matches_build_and_sources(self) -> None:
        self.assertEqual(abimod.check(), [])


if __name__ == "__main__":
    unittest.main()
