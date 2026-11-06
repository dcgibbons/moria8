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
