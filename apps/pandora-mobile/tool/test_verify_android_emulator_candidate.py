import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import verify_android_emulator_candidate as verifier


class AndroidEmulatorCandidateVerifierTest(unittest.TestCase):
    def test_emulator_identity_rejects_physical_serial(self):
        with self.assertRaisesRegex(verifier.base.VerificationError, "explicit emulator"):
            verifier.verify_emulator_identity("adb", "R58N12345", 35)

    def test_emulator_identity_rejects_non_qemu_target(self):
        outputs = iter(["device\n", "0\n"])
        with patch.object(verifier.base, "run_checked", side_effect=lambda command: next(outputs)):
            with self.assertRaisesRegex(verifier.base.VerificationError, "not reporting QEMU"):
                verifier.verify_emulator_identity("adb", "emulator-5554", 35)

    def test_emulator_identity_accepts_android_15(self):
        outputs = iter(["device\n", "1\n", "1\n", "35\n", "15\n"])
        with patch.object(verifier.base, "run_checked", side_effect=lambda command: next(outputs)):
            evidence = verifier.verify_emulator_identity("adb", "emulator-5554", 35)
        self.assertTrue(evidence["emulator_verified"])
        self.assertEqual(evidence["android_api_level"], 35)
        self.assertEqual(evidence["android_release"], "15")

    def test_emulator_identity_rejects_api_below_floor(self):
        outputs = iter(["device\n", "1\n", "1\n", "34\n"])
        with patch.object(verifier.base, "run_checked", side_effect=lambda command: next(outputs)):
            with self.assertRaisesRegex(verifier.base.VerificationError, "API level"):
                verifier.verify_emulator_identity("adb", "emulator-5554", 35)

    def test_resumed_activity_must_be_pandora_main_activity(self):
        verifier.require_resumed_activity(
            "mResumedActivity: ActivityRecord{abc com.banataosystems.pandora_mobile/.MainActivity}"
        )
        with self.assertRaisesRegex(verifier.base.VerificationError, "not the resumed activity"):
            verifier.require_resumed_activity(
                "mResumedActivity: ActivityRecord{abc com.android.settings/.Settings}"
            )

    def test_install_rejects_version_mismatch(self):
        outputs = iter([
            "Success\n",
            "package:/data/app/base.apk\n",
            "  versionCode=10 minSdk=24 targetSdk=36\n  versionName=0.4.0-rc.3\n",
        ])
        with patch.object(verifier.base, "run_checked", side_effect=lambda command: next(outputs)):
            with self.assertRaisesRegex(verifier.base.VerificationError, "version identity"):
                verifier.install_exact_candidate(
                    "adb", "emulator-5554", Path("candidate.apk"), "0.4.0-rc.4", "11"
                )

    def test_launch_verifies_process_and_resumed_activity(self):
        commands = []
        outputs = iter([
            "",
            "Starting: Intent\nStatus: ok\n",
            "1234\n",
            "topResumedActivity=ActivityRecord{abc com.banataosystems.pandora_mobile/.MainActivity}\n",
        ])

        def fake_run(command):
            commands.append(command)
            return next(outputs)

        with patch.object(verifier.base, "run_checked", side_effect=fake_run):
            pid = verifier.launch_and_verify("adb", "emulator-5554")
        self.assertEqual(pid, "1234")
        self.assertTrue(any(verifier.MAIN_ACTIVITY in command for command in commands))

    def test_crash_buffer_rejects_pandora_crash(self):
        crash = "FATAL EXCEPTION: main\nProcess: com.banataosystems.pandora_mobile, PID: 1234\n"
        with patch.object(verifier.base, "run_checked", return_value=crash):
            with self.assertRaisesRegex(verifier.base.VerificationError, "crash buffer"):
                verifier.verify_crash_buffer("adb", "emulator-5554")

    def test_event_writer_produces_jsonl(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "events.jsonl"
            verifier.emit_event(path, "apk_installed", source_sha="a" * 40, serial="emulator-5554")
            records = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]
        self.assertEqual(records[0]["event"], "apk_installed")
        self.assertEqual(records[0]["serial"], "emulator-5554")
        self.assertRegex(records[0]["at"], r"Z$")


if __name__ == "__main__":
    unittest.main()
