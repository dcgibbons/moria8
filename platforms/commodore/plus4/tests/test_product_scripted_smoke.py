#!/usr/bin/env python3
"""Breakpoint ownership regressions; no emulator or sockets required."""
import re
from types import SimpleNamespace
import unittest

import product_scripted_smoke as harness


class Monitor:
    def __init__(self):
        self.kwargs = None

    def break_at(self, address, **kwargs):
        self.kwargs = kwargs
        return f"break ${harness.normalize_addr(address)}"

    def send_command(self, command, **kwargs):
        self.kwargs = kwargs
        return command


def matches(command, cpu_port, overlay):
    """Evaluate emitted monitor conditions against independent hardware cases."""
    if " if " not in command:
        return True
    expression = command.split(" if ", 1)[1]
    memory = {1: cpu_port, 0x4000: overlay}
    expression = re.sub(r"@cpu:\$([0-9a-fA-F]+)",
                        lambda m: str(memory[int(m[1], 16)]), expression)
    expression = re.sub(r"\$([0-9a-fA-F]+)", r"0x\1", expression)
    return bool(eval(expression.replace("&&", "and"), {"__builtins__": {}}))


class BreakpointTests(unittest.TestCase):
    def monitor(self, c64=True, overlays=None):
        mon = Monitor()
        args = SimpleNamespace(symbols={".c64_test_input_idx": "1234"} if c64 else {},
                               overlay_cond_map=overlays or {}, current_overlay_addr="4000")
        harness.configure_breakpoints(mon, args)
        return mon

    def test_captured_kernal_false_hit_and_overlay_ownership(self):
        mon = self.monitor(overlays={"EA63": 5})
        command = mon.break_at("ea63", debug=True, deadline=42)
        self.assertEqual(mon.kwargs, {"debug": True, "deadline": 42})
        # Captured failure: KERNAL AND #$10, $01=$36, current_overlay=0.
        self.assertFalse(matches(command, 0x36, 0))
        # Even a stale Help tag must not allow firmware to trigger the swap.
        self.assertFalse(matches(command, 0x36, 5))
        # RAM visibility alone also cannot identify the Help owner.
        self.assertFalse(matches(command, 0x35, 0))
        self.assertTrue(matches(command, 0x35, 5))
        self.assertTrue(matches(command, 0x34, 5))

    def test_all_c64_port_mappings(self):
        mon = self.monitor()
        basic = mon.break_at(0xA123)
        kernal = mon.break_at(0xF123)
        # BASIC needs LORAM and HIRAM; KERNAL needs HIRAM only.
        # CHAREN does not affect either ROM. Hardware: c64/memory.s.
        basic_visible = {0x33, 0x37}
        kernal_visible = {0x32, 0x33, 0x36, 0x37}
        for port in range(0x30, 0x38):
            with self.subTest(port=port):
                self.assertEqual(matches(basic, port, 0), port not in basic_visible)
                self.assertEqual(matches(kernal, port, 0), port not in kernal_visible)

    def test_fixed_ram_checkpoint_keeps_original_handler(self):
        mon = self.monitor()
        self.assertEqual(mon.break_at(0x3000, deadline=17), "break $3000")
        self.assertEqual(mon.kwargs, {"deadline": 17})

    def test_other_ports_keep_overlay_filter_without_c64_port_reads(self):
        mon = self.monitor(c64=False, overlays={"EA63": 5})
        command = mon.break_at("EA63")
        self.assertNotIn("@cpu:$01", command)
        self.assertTrue(matches(command, 0x37, 5))
        self.assertFalse(matches(command, 0x35, 4))
        self.assertEqual(mon.break_at("A123"), "break $A123")


if __name__ == "__main__":
    unittest.main()
