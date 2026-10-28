import struct
import tempfile
import unittest
from pathlib import Path

from moria_playtest import abi as abimod
from moria_playtest import launch
from moria_playtest import nav
from moria_playtest.game import (Mode, Observation, classify, derive_rng, find_jsr,
                                 snapshot_cpu_clock)
from moria_playtest.ports import C128, PLUS4
from moria_playtest.screen import decode_rows, screen_code_to_char

ABI = abimod.Abi(labels={"zp_player_x": 0x2B, "zp_player_y": 0x2C, "zp_player_hp_lo": 0x2D,
                         "zp_player_mhp_lo": 0x2F, "zp_player_lvl": 0x33,
                         "zp_player_dlvl": 0x34, "zp_game_flags": 0x43, "zp_rng_0": 0x1A},
                 consts={**{name: value for name, (_, value) in abimod.tables()[1].items()},
                         **abimod.C64.kernal},
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

    def test_spell_list_prompt_is_on_the_last_screen_row(self) -> None:
        """player_magic_select_overlay.s draws the list's prompt on
        SCREEN_ROWS - 1: row 24 on the C64, row 23 on the 24-row ports (the
        Apple IIe looped book, list, cancel until its budget ran out, M6)."""
        list_rows = {0: "Mage Book", 24: "Cast which? (a-d, ESC)"}
        self.assertEqual(self.mode(obs(list_rows)), (Mode.SPELL, "list"))
        rows24 = abimod.Abi(ABI.labels, {**ABI.consts, "hal_layout_screen_rows": 24}, {})
        apple = obs({0: "Mage Book", 23: "Cast which? (a-d, ESC)"})
        apple.abi = rows24
        self.assertEqual(classify(apple, rows24, COMMAND_RET), (Mode.SPELL, "list"))

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

    def test_item_prompt_and_its_list(self) -> None:
        self.assertEqual(self.mode(obs({0: "Wear which item (a-c)?"})), (Mode.ITEM, "which"))
        self.assertEqual(self.mode(obs({0: "Quaff which potion (a-a)?"})), (Mode.ITEM, "which"))   # M4 round 40
        self.assertEqual(self.mode(obs({0: "               Inventory", 2: " a) Brass Lantern"})),
                         (Mode.ITEM, "list"))
        self.assertEqual(self.mode(obs({0: "               Inventory", 18: "Press any key"})),
                         (Mode.DISMISS, "anykey"))

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

    def test_find_jsr_to_any_of_several_targets_finds_the_first(self) -> None:
        code = bytes([0x20, 0x00, 0x30, 0x20, 0xB9, 0x10, 0x60])
        self.assertEqual(find_jsr(code, 0x1178, (0x10B9, 0x3000)), 0x1178 + 3)
        self.assertEqual(find_jsr(code, 0x1178, (0x10B9, 0x4000)), 0x1178 + 6)

    def test_c128_stops_inside_the_wait_loop(self) -> None:
        """The C128's key routines restore the MMU mode and common-RAM map
        helpers on entry: the driver stops at the wait loop's BEQ, after
        that, and returns through the loop's ``sta igk_key`` (M6 round m6d)."""
        from moria_playtest.game import Game

        igk_key = 0x270B
        body = bytes([0xEA, 0x20, 0x00, 0x30, 0x8A, 0x48, 0x98, 0x48,          # restore; push X, Y
                      0x20, 0x8C, 0x27, 0xF0, 0xFB,                              # jsr scan; beq poll
                      0x8D, igk_key & 0xFF, igk_key >> 8, 0x68, 0xA8, 0x68, 0xAA, 0x60])

        class Mon:
            def mem_get(self, start: int, length: int, bank: int = 0) -> bytes:
                return (body + bytes(128))[:length] if start in (0x26EC, 0x2990) else bytes(length)

        abi = abimod.Abi(labels={**ABI.labels, "igk_key": igk_key, "input_get_key": 0x26EC,
                                 "input_get_key_fast": 0x2990}, consts=ABI.consts, all_symbols={})
        game = Game(Mon(), abi, Path("."), port=C128)   # type: ignore[arg-type]
        self.assertEqual(game.key_stops(), (0x26EC + 11, 0x2990 + 11))
        self.assertEqual(game.key_exits, {0x26EC + 11: 0x26EC + 13, 0x2990 + 11: 0x2990 + 13})
        Mon.mem_get = lambda self, start, length, bank=0: bytes(length)   # not loaded: a cold boot
        self.assertEqual(Game(Mon(), abi, Path("."), port=C128).key_stops(), (0x26EC, 0x2990))   # type: ignore[arg-type]

    def test_c128_key_returns_through_the_routine_it_stopped_in(self) -> None:
        """The C128 scans the keyboard matrix itself (no KERNAL buffer): a key
        is returned from the routine stopped in, through its own exit."""
        from moria_playtest.game import Game
        from moria_playtest.vice import CMD_MEM_SET, CMD_REGISTERS_SET

        class Mon:
            def __init__(self) -> None:
                self.sent: list[tuple[str, object]] = []
            def send_mem_set(self, start: int, data: bytes, bank: int = 0) -> int:
                self.sent.append(("mem", (start, data)))
                return len(self.sent)
            def send_registers_set(self, values: dict[int, int]) -> int:
                self.sent.append(("regs", values))
                return len(self.sent)
            def send_resume(self) -> int:
                return 99
            def wait(self, request_id: int, command: int) -> None:
                assert command == (CMD_MEM_SET, CMD_REGISTERS_SET)[request_id - 1]
            def finish_resume(self, request_id: int) -> None:
                pass

        abi = abimod.Abi(labels={**ABI.labels, "igk_key": 0x270B}, consts=ABI.consts, all_symbols={})
        mon = Mon()
        game = Game(mon, abi, Path("."), port=C128)   # type: ignore[arg-type]
        game.reg_ids = {"A": 0, "PC": 3}
        game.key_exits = {0x26EC: 0x2707, 0x2990: 0x29C0}
        game._run_to_input = lambda wall0: "next"   # type: ignore[method-assign]
        game.last = Observation(1, 0x2990, 0xF0, 0, 0, 0, bytes(256), b"", b"", b"", [])
        self.assertEqual(game.press(0x4E), "next")
        self.assertEqual(mon.sent, [("mem", (0x270B, b"\x4e")), ("regs", {0: 0x4E, 3: 0x29C0})])
        self.assertEqual(game.keylog, [0x4E])

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


def d64_image(files: dict[str, bytes]) -> bytes:
    """A 35-track D64 holding ``files`` as closed PRGs: the directory on 18/1
    (one entry per file, a second directory sector after eight), each file's
    data on consecutive sectors of tracks 1-17."""
    image = bytearray(174848)
    free = ((track, sector) for track in range(1, 18) for sector in range(21))
    entries = []
    for name, data in files.items():
        chunks = [data[i:i + 254] for i in range(0, len(data), 254)] or [b""]
        sectors = [next(free) for _ in chunks]
        for index, (chunk, (track, sector)) in enumerate(zip(chunks, sectors)):
            link = sectors[index + 1] if index + 1 < len(chunks) else (0, len(chunk) + 1)
            at = launch.d64_offset(track, sector)
            image[at:at + 2 + len(chunk)] = bytes(link) + chunk
        entries.append(bytes([0x82, *sectors[0]]) + name.upper().encode().ljust(16, b"\xa0"))
    for page, start in enumerate(range(0, len(entries), 8)):
        at = launch.d64_offset(18, 1 + page)
        more = start + 8 < len(entries)
        image[at:at + 2] = bytes([18, 2 + page] if more else [0, 0xFF])
        for slot, entry in enumerate(entries[start:start + 8]):
            image[at + slot * 32 + 2:at + slot * 32 + 2 + len(entry)] = entry
    return bytes(image)


class CreatureFlagTest(unittest.TestCase):
    """The shipped tier data carries Umoria's flags (tools/parse_creatures.py
    map_mflags): CD_ANIMAL and CD_DRAGON for the slays, CM_MULTIPLY for
    breeding. Until 2026-10-25 animal came from CD_FROST, dragon from
    CD_ANIMAL, and nothing bred."""

    CF_ANIMAL, CF_DRAGON, CF_GROUP, CF_BREEDER = 0x08, 0x10, 0x20, 0x40   # core/monster.s

    def flags(self) -> dict[str, int]:
        from moria_playtest import knowledge
        return {name: f for names, tables in knowledge._tiers() for name, f in zip(names, tables["mflags"])}

    def test_breeders_animals_and_dragons(self) -> None:
        flags = self.flags()
        self.assertTrue(flags["White Worm mass"] & self.CF_BREEDER)   # Umoria cmove 0x00200022
        self.assertTrue(flags["Jackal"] & self.CF_ANIMAL)
        self.assertFalse(flags["Jackal"] & self.CF_DRAGON)
        self.assertTrue(flags["Young Blue Dragon"] & self.CF_DRAGON)
        self.assertFalse(flags["Kobold"] & (self.CF_ANIMAL | self.CF_BREEDER))

    def test_no_packs_upstream_has_none(self) -> None:
        self.assertFalse(any(f & self.CF_GROUP for f in self.flags().values()))


class EarlyCreatureTest(unittest.TestCase):
    """Thirty DL 1-5 creatures added to tier 1 (2026-10-25; Umoria
    data_creatures.cpp): Moria8 had shipped only Kobold, White Worm mass and
    Floating Eye there. They come after tier 1's original 24, so the
    tier-local indices that saves and tests use did not move."""

    ADDED = ("Giant White Centipede", "Giant Yellow Centipede", "White Icky-Thing",
             "Large White Snake", "Giant White Mouse",
             # the second batch, the same day (25 DL 1-5 creatures)
             "Large Brown Snake", "Grey Mushroom patch", "Blubbering Icky-Thing", "Metallic Green Centipede",
             "Novice Warrior", "Novice Rogue", "Giant Green Frog", "Blue Yeek", "Large Black Snake",
             "White Harpy", "Yellow Mushroom patch", "Metallic Blue Centipede", "Scruffy-Looking Hobbit",
             "Huge Brown Bat", "Giant White Ant", "Metallic Red Centipede", "Large Green Snake",
             "Drooling Harpy", "Radiation Eye", "Giant Black Centipede", "Giant Blue Centipede",
             "Large Grey Snake", "Black Yeek", "Grey Icky-Thing", "Giant Black Frog")

    def tier1(self):
        from moria_playtest import knowledge
        names, tables = knowledge._tiers()[1]      # tier0.s is the town
        return list(names), tables

    def test_added_after_the_original_members(self) -> None:
        names, tables = self.tier1()
        self.assertEqual(len(names), 54)
        self.assertEqual(tuple(names[24:]), self.ADDED)
        self.assertEqual(names[:3], ["Kobold", "White Worm mass", "Floating Eye"])   # unmoved
        self.assertTrue(all(1 <= tables["level"][i] <= 5 for i in range(24, 54)))

    def test_tier_2_keeps_its_original_order(self) -> None:
        from moria_playtest import knowledge
        names, _ = knowledge._tiers()[2]
        self.assertEqual(len(names), 35)
        self.assertEqual(tuple(names[32:]), ("Black Yeek", "Grey Icky-Thing", "Giant Black Frog"))   # DL 5 joins tier 2

    def test_upstream_stats(self) -> None:
        names, tables = self.tier1()
        mouse, snake = names.index("Giant White Mouse"), names.index("Large White Snake")
        self.assertEqual((tables["hd_num"][mouse], tables["hd_sides"][mouse], tables["ac"][mouse]), (1, 3, 4))
        self.assertTrue(tables["mflags"][mouse] & CreatureFlagTest.CF_BREEDER)        # Umoria 0x0020000A
        self.assertEqual((tables["hd_num"][snake], tables["hd_sides"][snake], tables["ac"][snake]), (3, 6, 30))


class DiskCheckTest(unittest.TestCase):
    """The harness refuses a disk not written from the program and symbols it
    reads (a stale disk after `make test` failed every worker at boot)."""

    def test_reads_every_file_across_directory_sectors(self) -> None:
        files = {f"f{n}": bytes(range(n % 256)) * (n + 1) for n in range(10)}
        files["big"] = bytes(range(256)) * 3   # several sectors, last one partly used
        self.assertEqual(launch.d64_files(d64_image(files)), files)

    def build(self, tmp: Path, disk_files: dict[str, bytes]) -> launch.Build:
        out = tmp / "c64"
        out.mkdir()
        for source in launch.C64_DISK_FILES.values():
            (out / source).write_bytes(source.encode() * 40)
        (tmp / "moria8-c64.d64").write_bytes(d64_image(disk_files))
        return launch.Build(tmp / "moria8-c64.d64", out / "moria8.prg", out / "main.vs")

    def test_matching_disk_passes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            disk = {name: source.encode() * 40 for name, source in launch.C64_DISK_FILES.items()}
            launch.check_disk(self.build(Path(tmp), disk))

    def test_stale_or_missing_file_names_it(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            disk = {name: source.encode() * 40 for name, source in launch.C64_DISK_FILES.items()}
            disk["moria64"] = b"old program"
            del disk["64.town"]
            with self.assertRaisesRegex(launch.StaleDisk, r"\(64\.town, moria64\); rebuild"):
                launch.check_disk(self.build(Path(tmp), disk))

    @unittest.skipUnless(launch.C64_DISK.exists(), "C64 disk not present")
    def test_shipping_disk_reads_every_file(self) -> None:
        self.assertEqual(set(launch.d64_files(launch.C64_DISK.read_bytes())), set(launch.C64_DISK_FILES))

    def test_crash_entry_needs_the_rom_visible(self) -> None:
        """A KERNAL crash entry is a crash only with the ROM banked in: the
        C64 reads $01 bit 1, the Plus/4 TED $FF13 bit 0."""
        from moria_playtest.game import Game
        from moria_playtest.ports import C64
        from moria_playtest.vice import StopInfo

        class Mon:
            ff13 = 0xD4
            def mem_get(self, start: int, length: int, bank: int = 0) -> bytes:
                assert (start, length, bank) == (0xFF13, 1, 6)
                return bytes([self.ff13])

        mon = Mon()
        plus4 = Game(mon, ABI, Path("."), port=PLUS4)   # type: ignore[arg-type]
        plus4.io = 6
        stop = StopInfo(pc=0xFFF6, registers={})
        self.assertIsNone(plus4._rom_status(stop))
        mon.ff13 = 0xD5
        self.assertEqual(plus4._rom_status(stop), "$FF13=$D5")
        c64 = Game(mon, ABI, Path("."), port=C64)   # type: ignore[arg-type]
        c64.reg_ids = {"01": 56}
        self.assertIsNone(c64._rom_status(StopInfo(pc=0xFCE2, registers={56: 0x35})))
        self.assertEqual(c64._rom_status(StopInfo(pc=0xFCE2, registers={56: 0x37})), "$01=$37")

    def test_plus4_shipping_disk_reads_every_file(self) -> None:
        build = launch.Build.shipping(PLUS4)
        if not build.disk.exists():
            self.skipTest("Plus/4 disk not present")
        self.assertEqual(set(launch.d64_files(build.disk.read_bytes())), set(PLUS4.disk_files))

    def test_d71_second_side_follows_the_first(self) -> None:
        self.assertEqual(launch.d64_offset(36, 0), launch.D64_SIZE)
        self.assertEqual(launch.d64_offset(53, 2), launch.D64_SIZE + launch.d64_offset(18, 2))

    def test_c128_shipping_disk_reads_every_file(self) -> None:
        build = launch.Build.shipping(C128)
        if not build.disk.exists():
            self.skipTest("C128 disk not present")
        self.assertEqual(set(launch.d64_files(build.disk.read_bytes())), set(C128.disk_files))
        launch.check_disk(build)

    def test_plus4_stale_disk_names_its_make_target(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "plus4"
            out.mkdir()
            for source in PLUS4.disk_files.values():
                (out / source).write_bytes(source.encode() * 40)
            disk = {name: source.encode() * 40 for name, source in PLUS4.disk_files.items()}
            disk["4.bank"] = b"old"
            (Path(tmp) / PLUS4.disk).write_bytes(d64_image(disk))
            build = launch.Build.from_out(Path(tmp), PLUS4)
            with self.assertRaisesRegex(launch.StaleDisk, r"\(4\.bank\); rebuild it with `make diskplus4`"):
                launch.check_disk(build)



class Apple2Test(unittest.TestCase):
    """The Apple IIe's 80-column text page and keyboard (mame.py)."""

    def test_text_page_decodes_through_the_game_character_map(self) -> None:
        from moria_playtest.mame import a2_char_map, apple2_text
        main, aux = bytearray(b"\xa0" * 0x400), bytearray(b"\xa0" * 0x400)
        text = [0x14, 0x08, 0x05, 0x20, 0x00, 0x3E, 0x44, 0x4C, 0x3A]   # "the @>DL:" in screen codes
        row = 21   # (21 & 7) * $80 + (21 >> 3) * $28
        for col, code in enumerate(text):
            (aux if col % 2 == 0 else main)[(row & 7) * 0x80 + (row >> 3) * 0x28 + col // 2] = a2_char_map(code)
        rows = decode_rows(apple2_text(bytes(main), bytes(aux)), 80)
        self.assertEqual(len(rows), 25)
        self.assertEqual(rows[21][:9], "the @>DL:")
        self.assertEqual(rows[24].strip(), "")

    def test_keys_are_the_ones_input_translate_maps_back(self) -> None:
        from moria_playtest.mame import apple2_keys
        self.assertEqual(apple2_keys(0x4E), ord("n"))     # unshifted letter
        self.assertEqual(apple2_keys(0xCE), ord("N"))     # shifted letter
        self.assertEqual(apple2_keys(0x9D), 0x08)         # cursor left
        self.assertEqual(apple2_keys(0x3E), ord(">"))
        self.assertEqual(apple2_keys(0x0D), 0x0D)



class X16MapTest(unittest.TestCase):
    """The X16 keeps its own copy of the map and rereads what can have
    changed: a byte a testbench command made the whole map cost each
    driver a core (M6)."""

    def game(self):
        from types import SimpleNamespace
        from moria_playtest.x16 import X16Game
        cols, rows, base = 198, 66, 0xA000
        tiles = bytearray(cols * rows)
        zp = {0x60: 60, 0x61: 20, 0x2B: 100, 0x2C: 30, 0x34: 1}   # view x/y, player x/y, dlvl

        class Mon:
            read = 0

            def _run(self, commands):
                return [zp[int(c.split()[1], 16)] for c in commands]

            def mem_get(self, start, length, bank):
                assert bank == ("map", 0)
                Mon.read += length
                return bytes(tiles[start - base:start - base + length])

        game = X16Game.__new__(X16Game)
        game.abi = SimpleNamespace(hal_layout_map_cols=cols, hal_layout_map_rows=rows, MAP_BASE=base,
                                   hal_layout_viewport_w=78, hal_layout_viewport_h=18,
                                   zp_view_x=0x60, zp_view_y=0x61, zp_player_x=0x2B, zp_player_y=0x2C,
                                   zp_player_dlvl=0x34)
        game.mon, game.keylog, game.step = Mon(), [], 1
        game.map, game.map_dlvl, game.map_step, game.map_keys = None, 0, 0, 0
        return game, tiles, zp, Mon, cols

    def test_rereads_what_can_have_changed(self) -> None:
        game, tiles, zp, mon, cols = self.game()
        self.assertEqual(len(game.read_map()), cols * 66)
        self.assertEqual(mon.read, cols * 66)                           # first: the whole map
        near, room, far = 30 * cols + 100, 30 * cols + 124, 60 * cols + 5
        tiles[near] = tiles[room] = tiles[far] = 0x0C
        game.keylog += [ord("L")]
        game.step += 1
        mon.read = 0
        tiles_seen = game.read_map()
        self.assertEqual((tiles_seen[near], tiles_seen[room], tiles_seen[far]), (0x0C, 0x0C, 0))
        self.assertLess(mon.read, cols * 66 // 4)                        # a move: the view and the room
        game.keylog += [ord("R"), ord("a")]                              # read a scroll: anything may change
        game.step += 1
        self.assertEqual(game.read_map()[far], 0x0C)
        tiles[far] = 0
        zp[0x34] = 2                                                     # a new level
        game.keylog += [ord("L")]
        game.step += 1
        self.assertEqual(game.read_map()[far], 0)



class X16BlockReadTest(unittest.TestCase):
    """An x16emu patched for block reads (RQB, RQV, STB; docs/BACKLOG.md)
    is read a block a command; a stock one, which answers the probe "ERR",
    a byte a command."""

    def monitor(self, patched: bool):
        from moria_playtest.x16 import X16Monitor
        ram = bytearray(range(256)) * 256

        class Process:
            sent: list[str] = []
            replies: list[str] = []

            def send(self, text):
                for command in text.split("\n"):
                    Process.sent.append(command)
                    op, *args = command.split()
                    if op == "RQB" and patched:
                        start, length = int(args[0], 16), int(args[1], 16)
                        Process.replies.append(ram[start:start + length].hex())
                    elif op in ("RQB", "RQV", "STB"):
                        Process.replies.append("ERR Unknown command")
                    elif op == "RQM":
                        Process.replies.append(f"{ram[int(args[0], 16)]:02x}")
                    else:
                        Process.replies.append("RDY")

            def receive(self, timeout):
                return Process.replies.pop(0)

        return X16Monitor(Process()), Process

    def test_patched_reads_a_block_a_command(self) -> None:
        mon, process = self.monitor(True)
        self.assertTrue(mon.block)
        process.sent.clear()
        self.assertEqual(mon.mem_get(0x0410, 32), bytes(range(0x10, 0x30)))
        self.assertEqual(process.sent, ["RQB 0410 20"])

    def test_stock_reads_a_byte_a_command(self) -> None:
        mon, process = self.monitor(False)
        self.assertFalse(mon.block)
        process.sent.clear()
        self.assertEqual(mon.mem_get(0x0410, 4), bytes(range(0x10, 0x14)))
        self.assertEqual(process.sent, ["RQM 0410", "RQM 0411", "RQM 0412", "RQM 0413"])


if __name__ == "__main__":
    unittest.main()
