import unittest
from types import SimpleNamespace

from moria_playtest import disk
from moria_playtest.session import Character

# c1541 -list of a save disk with another program's file (VICE 3.10).
LISTING = """D64 disk image recognised: save.d64, 35 tracks.
0 "save            " 01 2a
1    "moria8.id"        seq
26   "the.game"         seq
3    "other game"       prg
634 blocks free.
"""


class ListingTest(unittest.TestCase):
    def test_files_without_header_or_free_blocks(self) -> None:
        self.assertEqual(disk.parse_listing(LISTING), ["moria8.id", "the.game", "other game"])

    def test_a_disk_named_save_is_not_a_save(self) -> None:
        listing = '0 "save            " 01 2a\n1    "moria8.id"        seq\n'
        self.assertEqual(disk.parse_listing(listing), ["moria8.id"])


class LoadRetryFindingTest(unittest.TestCase):
    """Character.check_load_retries files a repeated disk load once per change."""

    def character(self, counts: list[int]) -> tuple[Character, list[tuple[str, str]]]:
        memory = iter(counts)
        game = SimpleNamespace(abi=SimpleNamespace(all_symbols={"asset_load_retries": [0x4BB2]}),
                               mon=SimpleNamespace(mem_get=lambda addr, n, bank: bytes([next(memory)])),
                               ram=0)
        character = Character.__new__(Character)
        character.worker = SimpleNamespace(game=game)
        character.load_retries = None
        character.result = SimpleNamespace(steps=7)
        filed: list[tuple[str, str]] = []
        character.file_finding = lambda kind, cls, detail, obs, pc=None: filed.append((kind, cls))
        return character, filed

    def test_a_change_between_level_entries_is_filed(self) -> None:
        character, filed = self.character([0, 0, 1, 1])
        for _ in range(4):
            character.check_load_retries(None)
        self.assertEqual(filed, [("load_retry", "game")])

    def test_the_first_reading_is_the_baseline(self) -> None:
        character, filed = self.character([5])
        character.check_load_retries(None)
        self.assertEqual(filed, [])



class AssetLoadFindingTest(unittest.TestCase):
    """2026-11-09: eight Plus/4 build-queue games sat on "Insert program disk"
    to their step budgets; the stuck load is a finding with its file name."""

    def test_the_finding_names_the_file_and_ends_the_character(self) -> None:
        memory = {0x1000: 4, 0x1001: 0x00, 0x1002: 0x20, 0x1003: 7, 0x1004: 3, 0x2000: b"4.ui"}
        symbols = {"alr_len": [0x1000], "alr_name_lo": [0x1001], "alr_name_hi": [0x1002],
                   "current_overlay": [0x1003], "asset_load_retries": [0x1004]}

        def mem_get(addr: int, n: int, bank: int) -> bytes:
            value = memory[addr]
            return value if isinstance(value, bytes) else bytes([value])

        game = SimpleNamespace(abi=SimpleNamespace(all_symbols=symbols), mon=SimpleNamespace(mem_get=mem_get), ram=0)
        character = Character.__new__(Character)
        character.worker = SimpleNamespace(game=game, snapshot=lambda name, state: None)
        character.goal = SimpleNamespace(name="clvl10")
        character.seed, character.snapshot = 1, None
        character.brain = SimpleNamespace(state=lambda: {})
        character.auditor = SimpleNamespace(command_sp=0xF0)
        character.result = SimpleNamespace(steps=2330, outcome="budget")
        filed: list[tuple[str, str, str]] = []
        character.file_finding = lambda kind, cls, detail, obs, pc=None: filed.append((kind, cls, detail))
        character.file_asset_load(SimpleNamespace(dlvl=1))
        self.assertEqual(character.result.outcome, "finding")
        self.assertEqual(filed[0][:2], ("asset_load", "game"))
        self.assertIn("b'4.ui'", filed[0][2])
        self.assertIn("overlay 7", filed[0][2])


if __name__ == "__main__":
    unittest.main()


class TextMonitorTest(unittest.TestCase):
    """2026-11-06: a C64 Balrog save after 1.18 million steps found the text
    monitor's connection reset; the next command opens a new one."""

    def test_a_dropped_connection_is_reopened(self) -> None:
        import socket
        server = socket.socket()
        server.bind(("127.0.0.1", 0))
        server.listen(2)
        monitor = disk.TextMonitor(server.getsockname()[1])
        try:
            monitor.command("first", settle=0.05)
            peer, _ = server.accept()
            peer.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, b"\x01\x00\x00\x00\x00\x00\x00\x00")
            peer.close()   # a reset, as VICE's was
            monitor.drain()
            self.assertIsNone(monitor.sock)
            monitor.command("again", settle=0.05)
            second, _ = server.accept()
            self.assertEqual(second.recv(16), b"again\n")
            second.close()
        finally:
            monitor.close()
            server.close()
