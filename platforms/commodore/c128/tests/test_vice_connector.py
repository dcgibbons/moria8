#!/usr/bin/env python3
from __future__ import annotations

import unittest
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))
from vice_connector import VICEConnector


class ResettingSocket:
    def recv(self, _size: int) -> bytes:
        raise ConnectionResetError("reset by peer")


class ClosedSocket:
    def recv(self, _size: int) -> bytes:
        return b""


class PromptSocket:
    def __init__(self) -> None:
        self.calls = 0

    def recv(self, _size: int) -> bytes:
        self.calls += 1
        if self.calls == 1:
            return b"(C:$1234) "
        return b""

    def gettimeout(self) -> float | None:
        return None

    def settimeout(self, _timeout: float | None) -> None:
        return


class VICEConnectorTests(unittest.TestCase):
    def test_wait_for_stop_reports_connection_reset(self) -> None:
        connector = VICEConnector()
        connector.sock = ResettingSocket()  # type: ignore[assignment]

        result = connector.wait_for_stop(pass_addr="1234", timeout=0.1)

        self.assertFalse(result.passed)
        self.assertEqual(result.reason, "monitor connection reset")

    def test_wait_for_stop_reports_closed_connection(self) -> None:
        connector = VICEConnector()
        connector.sock = ClosedSocket()  # type: ignore[assignment]

        result = connector.wait_for_stop(pass_addr="1234", timeout=0.1)

        self.assertFalse(result.passed)
        self.assertEqual(result.reason, "monitor connection closed")

    def test_wait_for_stop_still_reports_pass_breakpoint(self) -> None:
        connector = VICEConnector()
        connector.sock = PromptSocket()  # type: ignore[assignment]

        result = connector.wait_for_stop(pass_addr="1234", timeout=0.1)

        self.assertTrue(result.passed)


if __name__ == "__main__":
    unittest.main()
