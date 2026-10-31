import socket
import struct
import threading
import unittest

from moria_playtest import vice


def response(kind: int, request_id: int, body: bytes = b"", error: int = 0) -> bytes:
    return struct.pack("<BBIBBI", vice.STX, vice.API_VERSION, len(body), kind, error,
                       request_id) + body


class FakeVice:
    """Socketpair peer that answers scripted responses per received command."""

    def __init__(self, script):  # script: command -> callable(request_id) -> bytes
        self.client, self.server = socket.socketpair()
        self.script = script
        self.thread = threading.Thread(target=self.serve, daemon=True)
        self.thread.start()

    def serve(self) -> None:
        buf = b""
        while True:
            chunk = self.server.recv(4096)
            if not chunk:
                return
            buf += chunk
            while len(buf) >= 11:
                length = struct.unpack_from("<I", buf, 2)[0]
                if len(buf) < 11 + length:
                    break
                request_id = struct.unpack_from("<I", buf, 6)[0]
                command = buf[10]
                buf = buf[11 + length:]
                self.server.sendall(self.script[command](request_id))

    def monitor(self) -> vice.ViceMonitor:
        mon = vice.ViceMonitor(response_timeout=2.0)
        self.client.setblocking(False)
        mon._sock = self.client
        return mon


class ProtocolTest(unittest.TestCase):
    def test_encode_request_header(self) -> None:
        data = vice.encode_request(0x1234DEAD, vice.CMD_CHECKPOINT_SET, b"\xe2\xfc\xe3\xfc\x01\x01\x04\x01")
        self.assertEqual(data[:11].hex(), "0202" "08000000" "adde3412" "12")

    def test_decode_handles_partial_and_multiple_packets(self) -> None:
        raw = response(0x81, 7) + response(0x01, 8, b"\x02\x00\xaa\xbb")
        buf = bytearray(raw[:5])
        self.assertEqual(vice.decode_packets(buf), [])
        buf.extend(raw[5:])
        packets = vice.decode_packets(buf)
        self.assertEqual([(p.kind, p.request_id) for p in packets], [(0x81, 7), (0x01, 8)])
        self.assertEqual(packets[1].body, b"\x02\x00\xaa\xbb")
        self.assertEqual(buf, bytearray())

    def test_parse_registers(self) -> None:
        body = struct.pack("<H", 2) + bytes([3, 3]) + struct.pack("<H", 0x10B9) + bytes([3, 4, 0xF4, 0])
        self.assertEqual(vice.parse_registers(body), {3: 0x10B9, 4: 0xF4})

    def test_checkpoint_set_waits_for_checkpoint_info(self) -> None:
        info = struct.pack("<IBHHBBBBIIBB", 5, 0, 0x10B9, 0x10B9, 1, 1, 4, 0, 0, 0, 0, 0)
        fake = FakeVice({vice.CMD_CHECKPOINT_SET: lambda rid: response(vice.RESP_CHECKPOINT_INFO, rid, info)})
        self.assertEqual(fake.monitor().checkpoint_set(0x10B9), 5)

    def test_resume_discards_stale_stop_events(self) -> None:
        stale = response(vice.RESP_STOPPED, vice.EVENT_ID, b"\xcf\xe5")
        resumed = response(vice.RESP_RESUMED, vice.EVENT_ID, b"\xcf\xe5")
        hit = struct.pack("<IBHHBBBBIIBB", 2, 1, 0x10B9, 0x10B9, 1, 1, 4, 0, 1, 0, 0, 0)
        fresh = (response(vice.RESP_CHECKPOINT_INFO, vice.EVENT_ID, hit)
                 + response(vice.RESP_STOPPED, vice.EVENT_ID, b"\xb9\x10"))
        fake = FakeVice({
            vice.CMD_PING: lambda rid: stale + response(vice.CMD_PING, rid),
            vice.CMD_EXIT: lambda rid: response(vice.CMD_EXIT, rid) + resumed + fresh,
        })
        mon = fake.monitor()
        mon.ping()
        mon.resume()
        stop = mon.wait_stop(timeout=2.0)
        self.assertEqual((stop.pc, stop.checkpoint), (0x10B9, 2))

    def test_resource_set_sends_integers_little_endian(self) -> None:
        # As resource_get reads them; decimal text set Drive8TrueEmulation=0 as 48.
        mon = vice.ViceMonitor()
        sent: list[bytes] = []
        mon.call = lambda command, body=b"": sent.append(body)  # type: ignore[method-assign]
        mon.resource_set("AttachDevice9d0Readonly", 1)
        mon.resource_set("RemoteMonitorAddress", "127.0.0.1:1")
        name = b"AttachDevice9d0Readonly"
        self.assertEqual(sent[0], bytes([1, len(name)]) + name + bytes([4, 1, 0, 0, 0]))
        name, value = b"RemoteMonitorAddress", b"127.0.0.1:1"
        self.assertEqual(sent[1], bytes([0, len(name)]) + name + bytes([len(value)]) + value)

    def test_command_error_raises(self) -> None:
        fake = FakeVice({vice.CMD_MEM_GET: lambda rid: response(vice.CMD_MEM_GET, rid, error=0x02)})
        with self.assertRaises(vice.ViceCommandError):
            fake.monitor().mem_get(0, 1)

    def test_silent_peer_times_out(self) -> None:
        fake = FakeVice({vice.CMD_PING: lambda rid: b""})
        mon = fake.monitor()
        mon.response_timeout = 0.2
        with self.assertRaises(vice.ViceTimeout):
            mon.ping()


if __name__ == "__main__":
    unittest.main()


class RomArgsTest(unittest.TestCase):
    """Optional ROM images (maintainer, 2026-10-27): JiffyDOS by preference,
    any other KERNAL and 1541 pair later."""

    def test_unset_means_vice_own_roms(self) -> None:
        from moria_playtest.launch import rom_args
        self.assertEqual(rom_args({}), [])
        self.assertEqual(rom_args({"PLAYTEST_KERNAL": "", "PLAYTEST_DOS1541": ""}), [])

    def test_set_names_each_rom(self) -> None:
        import tempfile
        from pathlib import Path
        from moria_playtest.launch import rom_args
        with tempfile.TemporaryDirectory() as tmp:
            kernal, drive = Path(tmp) / "k.bin", Path(tmp) / "d.bin"
            kernal.write_bytes(b"\0" * 8192)
            drive.write_bytes(b"\0" * 16384)
            self.assertEqual(rom_args({"PLAYTEST_KERNAL": str(kernal), "PLAYTEST_DOS1541": str(drive)}),
                             ["-kernal", str(kernal.resolve()), "-dos1541", str(drive.resolve())])
            with self.assertRaises(FileNotFoundError):
                rom_args({"PLAYTEST_KERNAL": str(Path(tmp) / "missing.bin")})

    def test_plus4_requires_its_jiffydos_pair(self) -> None:
        """The Plus/4 has no REU and loads every overlay from the 1541, so it
        plays under JiffyDOS (maintainer, 2026-10-27) and refuses to run
        without it; the drive ROM is the C64's."""
        import tempfile
        from pathlib import Path
        from moria_playtest.launch import rom_args
        from moria_playtest.ports import PLUS4
        with self.assertRaisesRegex(FileNotFoundError, "PLAYTEST_PLUS4_KERNAL"):
            rom_args({"PLAYTEST_DOS1541": "x"}, PLUS4)
        with self.assertRaisesRegex(FileNotFoundError, "PLAYTEST_DOS1541"):
            rom_args({"PLAYTEST_PLUS4_KERNAL": "x"}, PLUS4)
        with tempfile.TemporaryDirectory() as tmp:
            kernal, drive = Path(tmp) / "k.bin", Path(tmp) / "d.bin"
            kernal.write_bytes(b"\0" * 16384)
            drive.write_bytes(b"\0" * 16384)
            env = {"PLAYTEST_PLUS4_KERNAL": str(kernal), "PLAYTEST_DOS1541": str(drive),
                   "PLAYTEST_KERNAL": "/the/c64/kernal.bin"}
            self.assertEqual(rom_args(env, PLUS4),
                             ["-kernal", str(kernal.resolve()), "-dos1541", str(drive.resolve())])
