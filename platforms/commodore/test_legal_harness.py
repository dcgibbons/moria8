#!/usr/bin/env python3
"""Configuration and evidence regressions; no emulator is launched."""
import argparse
from contextlib import ExitStack, redirect_stdout, redirect_stderr
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import MagicMock, patch

import test_legal as harness


class StartupStopped(RuntimeError):
    pass


class LegalHarnessTests(unittest.TestCase):
    def setUp(self):
        scratch = harness.ROOT / "build"
        scratch.mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix="legal-harness-", dir=scratch)
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.symbols = self.root / "alternate.sym"
        self.symbols.write_text(".label entry=$1234\n.label title_menu_loop=$2345\n")
        self.image = self.root / "alternate.d64"
        self.image.write_bytes(b"alternate disk")
        self.program = self.root / "alternate.prg"
        self.program.write_bytes(b"alternate program")
        self.vice = self.root / "configured-vice"
        self.c1541 = self.root / "configured-c1541"
        for tool in (self.vice, self.c1541):
            tool.write_text("#!/usr/bin/env sh\nexit 1\n")
            tool.chmod(0o700)

    def argv(self, port="c64"):
        return [port, "--symbols", str(self.symbols), "--disk-image", str(self.image),
                "--program", str(self.program), "--vice", str(self.vice),
                "--c1541", str(self.c1541), "--output", str(self.root / "evidence")]

    def startup(self, stack):
        process = MagicMock(returncode=0)
        process.poll.return_value = 0
        popen = stack.enter_context(patch.object(harness.subprocess, "Popen", return_value=process))
        stack.enter_context(patch.object(harness.threading, "Timer"))
        config = stack.enter_context(patch.object(harness, "vice_config", return_value="configured-vicerc"))
        stack.enter_context(patch.object(harness, "allocate_free_port", return_value=12345))
        monitor = stack.enter_context(patch.object(harness, "VICEConnector")).return_value
        # Stop at autostart, after the real dispatch has recorded its inputs.
        monitor.send_command.side_effect = ["OK", "OK", StartupStopped()]
        return popen, config, monitor

    def test_cli_launches_configured_artifacts_and_emulator_for_each_port(self):
        for port in ("c64", "c128", "plus4"):
            with self.subTest(port=port), ExitStack() as stack:
                popen, config, monitor = self.startup(stack)
                with redirect_stdout(io.StringIO()), self.assertRaises(StartupStopped):
                    harness.main(self.argv(port))
                command = popen.call_args.args[0]
                self.assertEqual(command[0], str(self.vice))
                self.assertEqual(command[command.index("-8") + 1], str(self.image))
                config.assert_called_once_with(str(self.vice))
                commands = [call.args[0] for call in monitor.send_command.call_args_list]
                initial = "2345" if port == "c128" else "1234"
                self.assertIn(f"break ${initial}", commands)
                program = self.program if port == "c64" else self.image
                self.assertIn(f'autostart "{program}"', commands)

    def test_missing_document_fixture_uses_configured_disk_tool_and_image(self):
        args = argparse.Namespace(port="c64", symbols=self.symbols, disk_image=self.image,
                                  program=self.program, vice=str(self.vice), c1541=str(self.c1541))
        output = self.root / "missing"
        with ExitStack() as stack:
            popen, _, _ = self.startup(stack)
            drive = stack.enter_context(patch.object(harness.subprocess, "run"))
            with self.assertRaises(StartupStopped):
                harness.run(args, output, "missing")
        fixture = output / "missing-license.d64"
        self.assertEqual(fixture.read_bytes(), self.image.read_bytes())
        self.assertEqual(drive.call_args_list[0].args[0],
                         [str(self.c1541), "-attach", str(fixture), "-delete", "license"])
        command = popen.call_args.args[0]
        self.assertEqual(command[command.index("-8") + 1], str(fixture))

    def test_repeated_failed_runs_preserve_all_previous_evidence(self):
        with ExitStack() as stack:
            self.startup(stack)
            with redirect_stdout(io.StringIO()), self.assertRaises(StartupStopped):
                harness.main(self.argv())
        first, = (self.root / "evidence").iterdir()
        for name in ("vice.log", "monitor.log", "memory.bin", "exit.txt"):
            (first / "title" / name).write_bytes(b"previous evidence: " + name.encode())
        before = {p: p.read_bytes() for p in first.rglob("*") if p.is_file()}
        with ExitStack() as stack:
            self.startup(stack)
            with redirect_stdout(io.StringIO()), self.assertRaises(StartupStopped):
                harness.main(self.argv())
        runs = list((self.root / "evidence").iterdir())
        self.assertEqual(len(runs), 2)
        self.assertEqual(before, {p: p.read_bytes() for p in first.rglob("*") if p.is_file()})
        second, = [p for p in runs if p != first]
        self.assertNotIn("previous evidence", (second / "title" / "monitor.log").read_text())
        self.assertTrue((second / "title" / "exit.txt").is_file())

    def test_missing_configured_input_is_rejected_before_launch(self):
        self.symbols.unlink()
        with patch.object(harness.subprocess, "Popen") as popen:
            with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as error:
                harness.main(self.argv())
        self.assertEqual(error.exception.code, 2)
        popen.assert_not_called()
        self.assertFalse((self.root / "evidence").exists())


if __name__ == "__main__":
    unittest.main()
