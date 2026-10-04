"""Process-state receipts only; no emulator or native acceptance is exercised."""
import json
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from core_android_emulator import run


class EmulatorCleanupEvidenceTest(unittest.TestCase):
    def exercise(self, exit_before_cleanup, command_status):
        events = []
        process = SimpleNamespace(returncode=None)
        def poll():
            events.append("poll")
            return process.returncode
        def terminate():
            events.append("terminate")
            process.returncode = -15
        def wait(**kwargs):
            events.append("wait")
            return process.returncode
        process.poll, process.terminate, process.wait = poll, terminate, wait
        process.kill = lambda: self.fail("Unexpected kill")
        def command(arguments, **kwargs):
            if arguments[0] == "private-command":
                process.returncode = exit_before_cleanup
                return subprocess.CompletedProcess(arguments, command_status)
            return subprocess.CompletedProcess(arguments, 0, "1\n", "private-token")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            commands = root / "commands.json"
            commands.write_text(json.dumps({"commands": [["private-command", "private-argument"]]}))
            with patch("core_android_emulator.subprocess.Popen", return_value=process), \
                 patch("core_android_emulator.subprocess.run", side_effect=command) as invoked:
                status = run(root / "sdk", root / "avd", root / "evidence", commands, "off", 480, "tall")
            text = (root / "evidence/android-boot-receipt.json").read_text()
            self.assertNotIn("private", text)
            self.assertEqual(events, ["poll", "poll", "terminate", "wait"])
            self.assertEqual(sum(call.args[0][0] == "private-command" for call in invoked.call_args_list), 1)
            return status, json.loads(text)

    def test_failed_journey_observes_running_emulator_before_intentional_termination(self):
        status, receipt = self.exercise(None, 1)
        self.assertEqual(status, 1)
        self.assertEqual(receipt["command_exit_code"], 1)
        self.assertEqual(receipt["emulator_process_before_cleanup"], {"state": "running", "exit_code": None})
        self.assertFalse(receipt["runtime_verified"])

    def test_failed_journey_preserves_already_exited_status_not_cleanup_status(self):
        status, receipt = self.exercise(-9, 1)
        self.assertEqual(status, 1)
        self.assertEqual(receipt["emulator_process_before_cleanup"], {"state": "exited", "exit_code": -9})

    def test_successful_command_does_not_infer_native_acceptance_or_spontaneous_failure(self):
        status, receipt = self.exercise(0, 0)
        self.assertEqual(status, 0)
        self.assertEqual(receipt["commands_completed"], 1)
        self.assertEqual(receipt["emulator_process_before_cleanup"], {"state": "exited", "exit_code": 0})
        self.assertFalse(receipt["runtime_verified"])
        self.assertFalse(receipt["production_verified"])


if __name__ == "__main__":
    unittest.main()
