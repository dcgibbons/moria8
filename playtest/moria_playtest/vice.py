"""VICE binary monitor client (protocol API version 2, VICE >= 3.5).

Protocol reference: VICE manual chapter 13 ("Binary monitor"). Every request
gets a response with the same request ID; events (checkpoint hit, stopped,
resumed, JAM) carry request ID 0xffffffff. Any command stops the emulator;
``resume`` (0xaa) continues it.

Requests can be pipelined: ``send`` queues a request without waiting, and
``wait`` collects the response for one request ID. Every socket wait is bounded
by ``response_timeout`` (60 s by maintainer decision); on expiry the caller is
expected to kill the emulator process.
"""

from __future__ import annotations

import select
import socket
import struct
import time
from dataclasses import dataclass, field

STX = 0x02
API_VERSION = 0x02
EVENT_ID = 0xFFFFFFFF

CMD_MEM_GET = 0x01
CMD_MEM_SET = 0x02
CMD_CHECKPOINT_GET = 0x11
CMD_CHECKPOINT_SET = 0x12
CMD_CHECKPOINT_DELETE = 0x13
CMD_CHECKPOINT_LIST = 0x14
CMD_CONDITION_SET = 0x22
CMD_REGISTERS_GET = 0x31
CMD_REGISTERS_SET = 0x32
CMD_DUMP = 0x41
CMD_UNDUMP = 0x42
CMD_RESOURCE_GET = 0x51
CMD_RESOURCE_SET = 0x52
CMD_KEYBOARD_FEED = 0x72
CMD_PING = 0x81
CMD_BANKS_AVAILABLE = 0x82
CMD_REGISTERS_AVAILABLE = 0x83
CMD_VICE_INFO = 0x85
CMD_EXIT = 0xAA
CMD_QUIT = 0xBB
CMD_RESET = 0xCC

RESP_CHECKPOINT_INFO = 0x11
RESP_REGISTER_INFO = 0x31
RESP_JAM = 0x61
RESP_STOPPED = 0x62
RESP_RESUMED = 0x63

CPU_OP_LOAD = 0x01
CPU_OP_STORE = 0x02
CPU_OP_EXEC = 0x04

MEMSPACE_MAIN = 0x00

DEFAULT_RESPONSE_TIMEOUT = 60.0

# Commands whose final response type differs from the command byte.
RESPONSE_KIND = {
    CMD_CHECKPOINT_GET: RESP_CHECKPOINT_INFO,
    CMD_CHECKPOINT_SET: RESP_CHECKPOINT_INFO,
    CMD_REGISTERS_GET: RESP_REGISTER_INFO,
    CMD_REGISTERS_SET: RESP_REGISTER_INFO,
}


class ViceError(Exception):
    """A VICE protocol or transport failure."""


class ViceTimeout(ViceError):
    """VICE did not answer within the response timeout; kill the emulator."""


class ViceCommandError(ViceError):
    def __init__(self, command: int, code: int) -> None:
        super().__init__(f"VICE command 0x{command:02x} failed with error 0x{code:02x}")
        self.command = command
        self.code = code


@dataclass(frozen=True)
class Packet:
    kind: int
    error: int
    request_id: int
    body: bytes

    @property
    def is_event(self) -> bool:
        return self.request_id == EVENT_ID


@dataclass(frozen=True)
class Checkpoint:
    number: int
    hit: bool
    start: int
    end: int
    stop: bool
    enabled: bool
    op: int
    temporary: bool
    hit_count: int
    ignore_count: int


@dataclass
class StopInfo:
    """Why and where the CPU stopped."""

    pc: int
    checkpoint: int | None = None
    jam: bool = False
    registers: dict[int, int] = field(default_factory=dict)


def encode_request(request_id: int, command: int, body: bytes = b"") -> bytes:
    return struct.pack("<BBIIB", STX, API_VERSION, len(body), request_id, command) + body


def decode_packets(buf: bytearray) -> list[Packet]:
    """Pop every complete response packet from ``buf``."""
    packets: list[Packet] = []
    while len(buf) >= 12:
        if buf[0] != STX:
            raise ViceError(f"lost protocol sync (byte 0x{buf[0]:02x})")
        length = struct.unpack_from("<I", buf, 2)[0]
        if len(buf) < 12 + length:
            break
        kind, error = buf[6], buf[7]
        request_id = struct.unpack_from("<I", buf, 8)[0]
        packets.append(Packet(kind, error, request_id, bytes(buf[12:12 + length])))
        del buf[:12 + length]
    return packets


def parse_checkpoint(body: bytes) -> Checkpoint:
    number, hit, start, end, stop, enabled, op, temp, hits, ignores = struct.unpack_from(
        "<IBHHBBBBII", body)
    return Checkpoint(number, bool(hit), start, end, bool(stop), bool(enabled), op,
                      bool(temp), hits, ignores)


def parse_registers(body: bytes) -> dict[int, int]:
    count = struct.unpack_from("<H", body, 0)[0]
    pos = 2
    regs: dict[int, int] = {}
    for _ in range(count):
        size = body[pos]
        reg_id = body[pos + 1]
        regs[reg_id] = int.from_bytes(body[pos + 2:pos + 1 + size], "little")
        pos += 1 + size
    return regs


class ViceMonitor:
    """One binary-monitor connection. Not thread safe."""

    def __init__(self, host: str = "127.0.0.1", port: int = 6502,
                 response_timeout: float = DEFAULT_RESPONSE_TIMEOUT) -> None:
        self.host = host
        self.port = port
        self.response_timeout = response_timeout
        self._sock: socket.socket | None = None
        self._buf = bytearray()
        self._next_id = 1
        self._responses: dict[int, list[Packet]] = {}
        self._events: list[Packet] = []
        self.bank_ids: dict[str, int] = {}
        self.register_ids: dict[str, int] = {}
        self.round_trips = 0

    # -- connection -------------------------------------------------------

    def connect(self, deadline: float) -> None:
        last: Exception | None = None
        while time.monotonic() < deadline:
            try:
                sock = socket.create_connection((self.host, self.port), timeout=1.0)
                sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                sock.setblocking(False)
                self._sock = sock
                return
            except OSError as exc:
                last = exc
                time.sleep(0.05)
        raise ViceTimeout(f"could not connect to VICE monitor on port {self.port}: {last}")

    def close(self) -> None:
        if self._sock is not None:
            try:
                self._sock.close()
            finally:
                self._sock = None

    # -- transport --------------------------------------------------------

    def send(self, command: int, body: bytes = b"") -> int:
        if self._sock is None:
            raise ViceError("not connected")
        request_id = self._next_id
        self._next_id = (self._next_id + 1) & 0x7FFFFFFF or 1
        data = encode_request(request_id, command, body)
        self._sendall(data)
        return request_id

    def _sendall(self, data: bytes) -> None:
        assert self._sock is not None
        view = memoryview(data)
        deadline = time.monotonic() + self.response_timeout
        while view:
            _, writable, _ = select.select([], [self._sock], [], max(0.0, deadline - time.monotonic()))
            if not writable:
                raise ViceTimeout("VICE monitor socket not writable")
            try:
                sent = self._sock.send(view)
            except OSError as exc:
                raise ViceError(f"VICE monitor send failed: {exc}") from exc
            view = view[sent:]

    def _pump(self, deadline: float) -> None:
        assert self._sock is not None
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise ViceTimeout(f"no VICE response within {self.response_timeout:.0f}s")
        readable, _, _ = select.select([self._sock], [], [], remaining)
        if not readable:
            raise ViceTimeout(f"no VICE response within {self.response_timeout:.0f}s")
        try:
            chunk = self._sock.recv(65536)
        except OSError as exc:
            raise ViceError(f"VICE monitor receive failed: {exc}") from exc
        if not chunk:
            raise ViceError("VICE closed the monitor connection")
        self._buf.extend(chunk)
        for packet in decode_packets(self._buf):
            if packet.is_event:
                self._events.append(packet)
            else:
                self._responses.setdefault(packet.request_id, []).append(packet)

    def wait(self, request_id: int, command: int) -> Packet:
        """Return the final response of ``command`` for ``request_id``.

        ``command`` may be a command byte; it is mapped to its response type.

        Some commands emit intermediate responses with the same ID (checkpoint
        list emits CHECKPOINT_INFO packets first); those are returned via
        ``wait_all``.
        """
        return self.wait_all(request_id, command)[-1]

    def wait_all(self, request_id: int, command: int) -> list[Packet]:
        kind = RESPONSE_KIND.get(command, command)
        deadline = time.monotonic() + self.response_timeout
        while True:
            packets = self._responses.get(request_id)
            if packets and any(p.kind == kind for p in packets):
                del self._responses[request_id]
                for packet in packets:
                    if packet.error:
                        raise ViceCommandError(command, packet.error)
                self.round_trips += 1
                return packets
            self._pump(deadline)

    def call(self, command: int, body: bytes = b"") -> Packet:
        return self.wait(self.send(command, body), command)

    # -- events -----------------------------------------------------------

    def drain_events(self) -> list[Packet]:
        events, self._events = self._events, []
        return events

    def wait_stop(self, timeout: float | None = None) -> StopInfo:
        """Block until the CPU stops (checkpoint, JAM); returns the stop info."""
        limit = self.response_timeout if timeout is None else timeout
        deadline = time.monotonic() + limit
        info: StopInfo | None = None
        while True:
            while self._events:
                event = self._events.pop(0)
                if event.kind == RESP_CHECKPOINT_INFO:
                    cp = parse_checkpoint(event.body)
                    if cp.hit:
                        info = info or StopInfo(pc=cp.start)
                        info.checkpoint = cp.number
                elif event.kind == RESP_REGISTER_INFO:
                    info = info or StopInfo(pc=0)
                    info.registers = parse_registers(event.body)
                elif event.kind == RESP_JAM:
                    pc = struct.unpack_from("<H", event.body)[0]
                    info = info or StopInfo(pc=pc)
                    info.jam = True
                    info.pc = pc
                    return info
                elif event.kind == RESP_STOPPED:
                    pc = struct.unpack_from("<H", event.body)[0]
                    info = info or StopInfo(pc=pc)
                    info.pc = pc
                    return info
            try:
                self._pump(deadline)
            except ViceTimeout:
                raise ViceTimeout(f"CPU did not stop within {limit:.0f}s") from None

    # -- commands ---------------------------------------------------------

    def ping(self) -> None:
        self.call(CMD_PING)

    def resume(self) -> None:
        """Resume the CPU and discard every event that predates the resume.

        Any command sent while the CPU runs stops it and emits register and
        stopped events, so stale stop events must not satisfy ``wait_stop``.
        """
        self.finish_resume(self.send(CMD_EXIT))

    def send_resume(self) -> int:
        return self.send(CMD_EXIT)

    def finish_resume(self, request_id: int) -> None:
        self.wait(request_id, CMD_EXIT)
        deadline = time.monotonic() + self.response_timeout
        while True:
            for index, event in enumerate(self._events):
                if event.kind == RESP_RESUMED:
                    del self._events[:index + 1]
                    return
            self._pump(deadline)

    def quit(self) -> None:
        try:
            self.send(CMD_QUIT)
        except ViceError:
            pass

    @staticmethod
    def mem_get_body(start: int, end: int, bank: int = 0, side_effects: bool = False) -> bytes:
        return struct.pack("<BHHBH", int(side_effects), start, end, MEMSPACE_MAIN, bank)

    def send_mem_get(self, start: int, length: int, bank: int = 0) -> int:
        return self.send(CMD_MEM_GET, self.mem_get_body(start, start + length - 1, bank))

    def recv_mem_get(self, request_id: int, length: int) -> bytes:
        body = self.wait(request_id, CMD_MEM_GET).body
        data = body[2:2 + length]
        if len(data) != length:
            raise ViceError(f"short memory read: {len(data)} of {length}")
        return data

    def mem_get(self, start: int, length: int, bank: int = 0) -> bytes:
        return self.recv_mem_get(self.send_mem_get(start, length, bank), length)

    def send_mem_set(self, start: int, data: bytes, bank: int = 0) -> int:
        body = struct.pack("<BHHBH", 0, start, start + len(data) - 1, MEMSPACE_MAIN, bank) + data
        return self.send(CMD_MEM_SET, body)

    def mem_set(self, start: int, data: bytes, bank: int = 0) -> None:
        self.wait(self.send_mem_set(start, data, bank), CMD_MEM_SET)

    def checkpoint_set(self, start: int, end: int | None = None, *, op: int = CPU_OP_EXEC,
                       stop: bool = True, temporary: bool = False) -> int:
        body = struct.pack("<HHBBBBB", start, start if end is None else end, int(stop), 1, op,
                           int(temporary), MEMSPACE_MAIN)
        return parse_checkpoint(self.call(CMD_CHECKPOINT_SET, body).body).number

    def checkpoint_delete(self, number: int) -> None:
        self.call(CMD_CHECKPOINT_DELETE, struct.pack("<I", number))

    def checkpoint_list(self) -> list[Checkpoint]:
        request_id = self.send(CMD_CHECKPOINT_LIST)
        packets = self.wait_all(request_id, CMD_CHECKPOINT_LIST)
        return [parse_checkpoint(p.body) for p in packets if p.kind == RESP_CHECKPOINT_INFO]

    def condition_set(self, number: int, expression: str) -> None:
        raw = expression.encode("ascii")
        self.call(CMD_CONDITION_SET, struct.pack("<IB", number, len(raw)) + raw)

    def registers(self) -> dict[int, int]:
        return parse_registers(self.call(CMD_REGISTERS_GET, bytes([MEMSPACE_MAIN])).body)

    def send_registers_set(self, values: dict[int, int]) -> int:
        """Set registers by id (``load_register_ids``); 16-bit values."""
        body = struct.pack("<BH", MEMSPACE_MAIN, len(values)) + b"".join(
            struct.pack("<BBH", 3, reg_id, value) for reg_id, value in values.items())
        return self.send(CMD_REGISTERS_SET, body)

    def registers_named(self) -> dict[str, int]:
        if not self.register_ids:
            self.load_register_ids()
        by_id = {v: k for k, v in self.register_ids.items()}
        return {by_id.get(k, str(k)): v for k, v in self.registers().items()}

    def load_register_ids(self) -> dict[str, int]:
        body = self.call(CMD_REGISTERS_AVAILABLE, bytes([MEMSPACE_MAIN])).body
        count = struct.unpack_from("<H", body, 0)[0]
        pos = 2
        ids: dict[str, int] = {}
        for _ in range(count):
            size = body[pos]
            reg_id = body[pos + 1]
            name_len = body[pos + 3]
            name = body[pos + 4:pos + 4 + name_len].decode("ascii", "replace")
            ids[name] = reg_id
            pos += 1 + size
        self.register_ids = ids
        return ids

    def load_bank_ids(self) -> dict[str, int]:
        body = self.call(CMD_BANKS_AVAILABLE).body
        count = struct.unpack_from("<H", body, 0)[0]
        pos = 2
        ids: dict[str, int] = {}
        for _ in range(count):
            size = body[pos]
            bank_id = struct.unpack_from("<H", body, pos + 1)[0]
            name_len = body[pos + 3]
            name = body[pos + 4:pos + 4 + name_len].decode("ascii", "replace")
            ids[name] = bank_id
            pos += 1 + size
        self.bank_ids = ids
        return ids

    def bank(self, name: str) -> int:
        if not self.bank_ids:
            self.load_bank_ids()
        return self.bank_ids[name]

    def dump(self, path: str, *, save_roms: bool = False, save_disks: bool = True) -> None:
        raw = path.encode()
        self.call(CMD_DUMP, struct.pack("<BBB", int(save_roms), int(save_disks), len(raw)) + raw)

    def undump(self, path: str) -> int:
        raw = path.encode()
        body = self.call(CMD_UNDUMP, struct.pack("<B", len(raw)) + raw).body
        return struct.unpack_from("<H", body)[0]

    def keyboard_feed(self, petscii: bytes) -> None:
        self.call(CMD_KEYBOARD_FEED, struct.pack("<B", len(petscii)) + petscii)

    def resource_get(self, name: str) -> str | int:
        raw = name.encode()
        body = self.call(CMD_RESOURCE_GET, struct.pack("<B", len(raw)) + raw).body
        kind, length = body[0], body[1]
        value = body[2:2 + length]
        return value.decode() if kind == 0 else int.from_bytes(value, "little")

    def resource_set(self, name: str, value: str | int) -> None:
        raw_name = name.encode()
        # An integer goes little-endian, as resource_get reads it back: its
        # decimal text set "0" as 48.
        raw_value = value.to_bytes(4, "little") if isinstance(value, int) else value.encode()
        kind = 1 if isinstance(value, int) else 0
        body = (struct.pack("<BB", kind, len(raw_name)) + raw_name
                + struct.pack("<B", len(raw_value)) + raw_value)
        self.call(CMD_RESOURCE_SET, body)

    def vice_info(self) -> dict[str, str]:
        body = self.call(CMD_VICE_INFO).body
        version_len = body[0]
        version = body[1:1 + version_len]
        rev_len = body[1 + version_len]
        revision = body[2 + version_len:2 + version_len + rev_len]
        return {"version": ".".join(str(b) for b in version),
                "svn_revision": str(int.from_bytes(revision, "little"))}
