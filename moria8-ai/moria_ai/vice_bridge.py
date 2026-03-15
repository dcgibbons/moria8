"""VICE binary monitor protocol client.

A robust implementation of the VICE binary monitor protocol (v1/v2).
Provides high-fidelity logging and automatic protocol synchronization.
"""

from __future__ import annotations

import logging
import socket
import struct
import threading
import time
from dataclasses import dataclass
from typing import Optional

logger = logging.getLogger(__name__)

# Protocol constants
STX = 0x02
DEFAULT_API_VERSION = 0x02

# Command types
CMD_MEMORY_GET = 0x01
CMD_MEMORY_SET = 0x02
CMD_CHECKPOINT_SET = 0x12
CMD_CHECKPOINT_DELETE = 0x13
CMD_REGISTERS_GET = 0x31
CMD_KEYBOARD_FEED = 0x72
CMD_PING = 0x81
CMD_DISPLAY_GET = 0x84
CMD_EXIT = 0xAA
CMD_QUIT = 0xBB

# Event codes
EVT_STOPPED = 0x62
EVT_RESUMED = 0x63

# Error codes
ERR_OK = 0x00

class BridgeError(Exception):
    """Base error for VICE communication."""

class TimeoutError(BridgeError):
    """Timed out waiting for a response from VICE."""

@dataclass
class StoppedEvent:
    """Received when VICE hits a breakpoint."""
    pc: int

@dataclass
class Response:
    """A parsed binary monitor packet (Response or Event)."""
    command_type: int
    api: int
    err: int
    req_id: int
    body: bytes

    @property
    def is_event(self) -> bool:
        return self.req_id == 0xFFFFFFFF

class ViceBridge:
    """High-reliability client for the VICE binary monitor."""

    def __init__(self, host: str = "127.0.0.1", port: int = 6502):
        self.host = host
        self.port = port
        self.api_version = DEFAULT_API_VERSION
        self._sock: Optional[socket.socket] = None
        self._request_id = 0
        self._lock = threading.Lock()
        self._recv_buf = bytearray()
        self._event_queue: list[Response] = []

    def connect(self, timeout: float = 5.0) -> None:
        """Connect to VICE."""
        self._sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        self._sock.settimeout(timeout)
        
        try:
            self._sock.connect((self.host, self.port))
            logger.info("TCP connected to VICE at %s:%d", self.host, self.port)
        except Exception as e:
            self._sock = None
            raise BridgeError(f"Connection failed: {e}")
            
        self._recv_buf.clear()
        self._event_queue.clear()
        self._request_id = 0

    def disconnect(self) -> None:
        """Gracefully close the connection."""
        if self._sock:
            try:
                self._sock.close()
            except OSError:
                pass
            self._sock = None
            logger.info("Disconnected from VICE")

    def _send_packet(self, command: int, body: bytes = b"") -> int:
        """Construct and send an 11-byte request header + body."""
        if not self._sock:
            raise BridgeError("Not connected")
        
        self._request_id = (self._request_id + 1) & 0xFFFFFFFF
        # Header: STX(1), API(1), BodyLen(4), ReqID(4), Command(1)
        header = struct.pack("<BBIIB", STX, self.api_version, len(body), self._request_id, command)
        
        packet = header + body
        logger.debug(">>> SEND [%d bytes] Cmd: 0x%02x, ID: %d", len(packet), command, self._request_id)
        
        with self._lock:
            self._sock.sendall(packet)
        return self._request_id

    def _recv_exact(self, n: int, timeout: float) -> bytes:
        """Read exactly N bytes or raise TimeoutError."""
        deadline = time.monotonic() + timeout
        while len(self._recv_buf) < n:
            rem = deadline - time.monotonic()
            if rem <= 0:
                raise TimeoutError(f"Wait timeout (buf_len: {len(self._recv_buf)})")
            
            self._sock.settimeout(rem)
            try:
                chunk = self._sock.recv(max(4096, n - len(self._recv_buf)))
                if not chunk:
                    raise BridgeError("VICE closed connection")
                self._recv_buf.extend(chunk)
            except socket.timeout:
                raise TimeoutError("Socket timeout")

        res = bytes(self._recv_buf[:n])
        del self._recv_buf[:n]
        return res

    def _read_packet(self, timeout: float) -> Response:
        """Read a 12-byte response header + body. Synchronizes on STX."""
        # 1. Sync on STX (0x02)
        while True:
            b = self._recv_exact(1, timeout)
            if b[0] == STX:
                break
            logger.debug("Discarding leading byte: 0x%02X", b[0])

        # 2. Read remaining 11 bytes of header
        # API(1), BodyLen(4), CmdType(1), Error(1), ReqID(4)
        h = self._recv_exact(11, timeout)
        api, blen, ctype, err, rid = struct.unpack("<BIBBI", h)
        
        # 3. Read body
        body = self._recv_exact(blen, timeout) if blen > 0 else b""
        
        resp = Response(ctype, api, err, rid, body)
        
        if resp.is_event:
            logger.debug("<<< RECV EVENT  Cmd: 0x%02x, Len: %d", ctype, blen)
        else:
            logger.debug("<<< RECV RESP   Cmd: 0x%02x, Err: 0x%02x, ID: %d", ctype, err, rid)
            
        return resp

    def _poll_until_response(self, req_id: int, timeout: float) -> Response:
        """Read packets until we find the one matching req_id. Queues events."""
        deadline = time.monotonic() + timeout
        while True:
            resp = self._read_packet(deadline - time.monotonic())
            
            if resp.is_event:
                self._event_queue.append(resp)
            elif resp.req_id == req_id:
                if resp.err != ERR_OK:
                    raise BridgeError(f"VICE Error 0x{resp.err:02x}")
                return resp

    def ping(self) -> None:
        """Verify the bridge is alive."""
        rid = self._send_packet(CMD_PING)
        self._poll_until_response(rid, 2.0)

    def memory_get(self, start: int, end: int, memspace: int = 0) -> bytes:
        """Read memory range. Body: SideEffects(1), Start(2), End(2), Space(1), Bank(2)"""
        body = struct.pack("<BHHBH", 0x00, start, end, memspace, 0)
        rid = self._send_packet(CMD_MEMORY_GET, body)
        resp = self._poll_until_response(rid, 2.0)
        # Body starts with 2-byte length
        if len(resp.body) < 2: return b""
        dlen = struct.unpack("<H", resp.body[:2])[0]
        return resp.body[2:2+dlen]

    def checkpoint_set(self, start: int, end: int, stop: bool = True, enabled: bool = True) -> int:
        """Set a breakpoint. Returns checkpoint ID."""
        # Body: Start(2), End(2), Stop(1), Enabled(1), Op(1), Temp(1)
        body = struct.pack("<HHBBBB", start, end, stop, enabled, 0x04, False)
        rid = self._send_packet(CMD_CHECKPOINT_SET, body)
        resp = self._poll_until_response(rid, 2.0)
        return struct.unpack("<I", resp.body[:4])[0]

    def checkpoint_delete(self, cp_id: int) -> None:
        rid = self._send_packet(CMD_CHECKPOINT_DELETE, struct.pack("<I", cp_id))
        self._poll_until_response(rid, 2.0)

    def keyboard_feed(self, text: str | bytes) -> None:
        if isinstance(text, str):
            text = text.encode("latin-1")
        # Body: Len(1), Keys(N)
        body = struct.pack("<B", len(text)) + text
        rid = self._send_packet(CMD_KEYBOARD_FEED, body)
        self._poll_until_response(rid, 2.0)

    def continue_execution(self) -> None:
        rid = self._send_packet(CMD_EXIT)
        self._poll_until_response(rid, 2.0)

    def wait_for_stop(self, timeout: float = 10.0) -> StoppedEvent:
        """Check queue for event, or read until one arrives."""
        deadline = time.monotonic() + timeout
        while True:
            # Check queue first
            for i, ev in enumerate(self._event_queue):
                if ev.command_type == EVT_STOPPED:
                    del self._event_queue[i]
                    pc = struct.unpack("<H", ev.body[:2])[0] if len(ev.body) >= 2 else 0
                    return StoppedEvent(pc)

            # Read next packet and queue it if it's an event
            resp = self._read_packet(deadline - time.monotonic())
            if resp.is_event:
                self._event_queue.append(resp)

    def display_get(self) -> bytes:
        rid = self._send_packet(CMD_DISPLAY_GET, struct.pack("<BB", 0, 0))
        return self._poll_until_response(rid, 2.0).body

    def registers_get(self) -> dict[str, int]:
        rid = self._send_packet(CMD_REGISTERS_GET, b"\x00")
        resp = self._poll_until_response(rid, 2.0)
        regs = {}
        if len(resp.body) < 2: return regs
        count = struct.unpack("<H", resp.body[:2])[0]
        off = 2
        for _ in range(count):
            if off + 1 > len(resp.body): break
            item_size = resp.body[off]
            if item_size == 0:
                off += 1
                continue
            reg_id = resp.body[off + 1]
            val_size = item_size - 1
            if val_size == 1:
                val = resp.body[off + 2]
            elif val_size == 2:
                val = struct.unpack("<H", resp.body[off+2:off+4])[0]
            else:
                val = 0
            
            names = {3: 'pc', 35: 'pc', 0: 'a', 53: 'a', 1: 'x', 54: 'x', 2: 'y', 55: 'y'}
            if reg_id in names: regs[names[reg_id]] = val
            
            off += 1 + item_size
        return regs
