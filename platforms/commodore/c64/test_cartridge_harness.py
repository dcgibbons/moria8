#!/usr/bin/env python3
"""Startup transport and evidence regressions; no emulator or sockets needed."""
import json
import io
import os
import subprocess
import sys
import threading
from pathlib import Path
import re
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import test_cartridge as harness


PROMPT = "(C:$e5d4) "


def registers(pc):
    return ("  ADDR A X Y SP 00 01 NV-BDIZC LIN CYC STOPWATCH\n"
            f".;{pc:04x} 00 00 00 ff 2f 36 00110000 000 000 0\n(C:${pc:04x}) ")


class Process:
    pid = 1234

    def __init__(self):
        self.returncode = None

    def poll(self):
        return self.returncode

    def kill(self):
        self.returncode = -9

    def terminate(self):
        self.returncode = -15

    def wait(self, timeout=None):
        return self.returncode


class Timer:
    def __init__(self, delay, callback):
        assert 0 <= delay <= 30

    def start(self):
        pass

    def cancel(self):
        pass


class Monitor:
    def __init__(self, process, crash=False):
        self.process = process
        self.crash = crash
        self.pc = 0xE5D4
        self.breaks = []
        self.trace = []

    def connect(self):
        self.trace.append("connect")

    def close(self):
        pass

    def send_command(self, command, **kwargs):
        self.trace.append(command)
        if command.startswith("pb "):
            script = Path(command.split('"')[1]).read_text()
            self.trace.append(script)
            self.breaks = [int(v, 16) for v in re.findall(r"break \$([0-9a-f]+)", script)]
        elif command.startswith("autostart") or command == "reset 1":
            assert self.breaks == [0x080E], "Entry must be armed before startup resumes"
            if self.crash:
                if self.crash != "alive":
                    self.process.returncode = -11
                raise ConnectionError("monitor connection closed")
            self.pc = self.breaks[0]
        elif command == "g":
            self.pc = self.breaks[-1]
            return f".C:{self.pc:04x}  EA NOP\n(C:${self.pc:04x}) "
        elif command == "quit":
            self.process.returncode = 0
            return ""
        return registers(self.pc)


class HarnessTests(unittest.TestCase):
    def setUp(self):
        (harness.ROOT / "build").mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=harness.ROOT / "build", prefix="harness-unit-")
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.args = SimpleNamespace(output=root / "evidence", symbols=root / "main.sym",
            disk_symbols=root / "main.sym", disk_image=root / "program.d64",
            crt=root / "game.crt", vice="x64sc", ntsc=False)
        self.args.symbols.write_text(".label entry=$080e\n.label title_menu_loop=$4000\n")
        self.args.crt.write_bytes(b"fixture")
        harness.prepare_run(self.args)

    def experiment(self, disk=False, crash=False):
        process = Process()
        monitor = Monitor(process, crash=crash)
        def start_process(*args, **kwargs):
            self.assertTrue(os.isatty(kwargs["stdout"]))
            os.write(kwargs["stdout"], b"fixture boot record\n")
            return process
        with patch.object(harness, "allocate_free_port", return_value=12345), \
             patch.object(harness, "vice_config", return_value="fixture-config"), \
             patch.object(harness.subprocess, "Popen", side_effect=start_process) as launch, \
             patch.object(harness, "VICEConnector", return_value=monitor), \
             patch.object(harness.threading, "Timer", Timer):
            exp = harness.Experiment(self.args, disk_build=disk)
        return exp, monitor, launch.call_args.args[0]

    def test_entry_breakpoint_precedes_disk_autostart(self):
        exp, monitor, command = self.experiment(disk=True)
        exp.close()
        self.assertLess(monitor.trace.index("r\n"), next(i for i, s in enumerate(monitor.trace) if s.startswith("autostart")))
        # Startup already stopped at entry; only title startup needs a 'g'.
        self.assertEqual(monitor.trace.count("g"), 1)
        self.assertNotIn("-logfile", command)
        self.assertEqual(exp.log.name, str(exp.out / "console.log"))
        self.assertIn(b"fixture boot record", (exp.out / "console.log").read_bytes())
        result = json.loads((exp.out / "result.json").read_text())
        self.assertEqual(result["pid"], 1234)
        self.assertEqual(result["returncode"], 0)
        self.assertFalse(result["watchdog_fired"])

    def test_entry_breakpoint_precedes_cartridge_reset(self):
        exp, monitor, _ = self.experiment()
        exp.close()
        self.assertIn("reset 1", monitor.trace)
        self.assertNotIn("g", monitor.trace)

    def test_stale_greeting_cannot_complete_ready_handshake(self):
        exp, _, _ = self.experiment()
        replies = iter((PROMPT, PROMPT + "autostarting test.prg #0\n"))
        fake = SimpleNamespace(send_command=lambda *a, **k: next(replies),
                               read_until_prompt=lambda **k: registers(0xE5D4), close=lambda: None)
        exp.mon = fake
        self.assertIn(".;e5d4", exp.batch([]))
        self.assertIn(".;e5d4", exp.batch([]))
        exp.proc.returncode = 0
        exp.close()

    def test_monitor_syntax_errors_fail_instead_of_being_silently_accepted(self):
        exp, monitor, _ = self.experiment()
        exp.mon = SimpleNamespace(send_command=lambda *a, **k: "ERROR -- Wrong syntax:\n" + PROMPT,
                                  close=lambda: None)
        with self.assertRaisesRegex(AssertionError, "Wrong syntax"):
            exp.cmd("bad-command")
        exp.proc.returncode = 0
        exp.close()

    def test_crash_records_pending_command_and_observed_signal(self):
        with self.assertRaises(ConnectionError):
            self.experiment(disk=True, crash=True)
        out = self.args.output / "assets/attempt-1"
        events = [json.loads(line) for line in (out / "events.jsonl").read_text().splitlines()]
        error = next(e for e in events if e["event"] == "monitor_error")
        self.assertEqual(error["returncode"], -11)
        self.assertEqual(error["phase"], "autostart")
        self.assertFalse(error["watchdog_fired"])
        self.assertIn('autostart "', (out / "monitor.log").read_text())

    def test_watchdog_kill_is_distinct_from_natural_failure(self):
        exp, _, _ = self.experiment()
        exp.watchdog()
        exp.close()
        result = json.loads((exp.out / "result.json").read_text())
        self.assertTrue(result["watchdog_fired"])
        self.assertEqual(result["termination_action"], "watchdog_kill")
        self.assertEqual(result["returncode"], -9)

    def test_live_disconnect_status_is_recorded_before_cleanup(self):
        with self.assertRaises(ConnectionError):
            self.experiment(disk=True, crash="alive")
        out = self.args.output / "assets/attempt-1"
        events = [json.loads(line) for line in (out / "events.jsonl").read_text().splitlines()]
        error = next(e for e in events if e["event"] == "monitor_error")
        self.assertIsNone(error["returncode"])
        self.assertFalse(error["watchdog_fired"])
        result = json.loads((out / "result.json").read_text())
        self.assertEqual(result["termination_action"], "monitor_quit")
        self.assertEqual(result["returncode"], 0)

    def test_watchdog_kills_before_writing_diagnostics(self):
        exp, _, _ = self.experiment()
        with patch.object(exp, "event", side_effect=OSError("evidence disk unavailable")):
            with self.assertRaises(OSError):
                exp.watchdog()
        self.assertEqual(exp.proc.returncode, -9)
        exp.close()

    def test_runs_cannot_reuse_old_evidence(self):
        first = self.args.output
        other = SimpleNamespace(output=first.parent)
        harness.prepare_run(other)
        self.assertNotEqual(first, other.output)
        self.assertEqual(first.parent, other.output.parent)

    def test_console_output_survives_a_real_child_sigkill(self):
        master, slave = harness.pty.openpty()
        os.set_blocking(master, False)
        path = self.args.output / "killed-console.log"
        capture = SimpleNamespace(console_master=master, console_stop=threading.Event(),
            log=path.open("wb", buffering=0), event=lambda *a, **k: None)
        child = subprocess.Popen([sys.executable, "-c",
            "import os,signal; print('evidence before kill'); os.kill(os.getpid(),signal.SIGKILL)"],
            stdout=slave, stderr=subprocess.STDOUT)
        os.close(slave)
        reader = threading.Thread(target=harness.Experiment.capture_console, args=(capture,))
        reader.start()
        try:
            self.assertEqual(child.wait(timeout=3), -9)
        finally:
            if child.poll() is None:
                child.kill()
                child.wait(timeout=1)
            capture.console_stop.set()
            reader.join(timeout=1)
            os.close(master)
            capture.log.close()
        self.assertIn(b"evidence before kill", path.read_bytes())

    def test_stop_wakeup_drains_final_console_bytes(self):
        for already_stopped in (False, True):
            with self.subTest(already_stopped=already_stopped):
                stop = threading.Event()
                if already_stopped:
                    stop.set()
                capture = SimpleNamespace(console_master=123, console_stop=stop,
                                          log=io.BytesIO(), event=lambda *a, **k: None)

                def child_exited(timeout):
                    # Bytes arrive after the first empty read, as cleanup wakes
                    # the reader. The final output must still be drained.
                    stop.set()
                    return True

                with patch.object(stop, "wait", side_effect=child_exited), \
                     patch.object(harness.os, "read", side_effect=(
                         BlockingIOError(), b"last console ", b"bytes\n", BlockingIOError())) as read:
                    harness.Experiment.capture_console(capture)
                self.assertEqual(capture.log.getvalue(), b"last console bytes\n")
                self.assertEqual(read.call_count, 4)


if __name__ == "__main__":
    unittest.main()
