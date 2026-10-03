"""Test receipt parsing; these are not Android runtime acceptance tests."""
import unittest
from core_android_device import AndroidDevice, DeviceFailure, parse_ime_visibility, parse_metrics, parse_package_evidence


class DeviceReceiptTest(unittest.TestCase):
    def test_ime_applied_false_overrides_stale_requested_visibility(self):
        self.assertFalse(parse_ime_visibility("mInputShown=false imeVisible=true"))
        self.assertTrue(parse_ime_visibility("mInputShown=true"))
        self.assertFalse(parse_ime_visibility("mShowRequested=true"))

    def test_missing_metrics_are_not_reported_as_zero_or_optimized(self):
        result = parse_metrics("No process found", "No process found")
        self.assertFalse(result["frame_metrics_available"])
        self.assertFalse(result["memory_metrics_available"])
        self.assertNotIn("janky_frames", result)

    def test_available_android_metrics_are_preserved(self):
        result = parse_metrics("Total frames rendered: 80\nJanky frames: 5 (6.25%)\n"
                               "95th percentile: 24ms", "TOTAL PSS: 125000")
        self.assertEqual(result["frames_rendered"], 80)
        self.assertEqual(result["janky_frames"], 5)
        self.assertEqual(result["frame_p95_ms"], 24)
        self.assertEqual(result["total_pss_kib"], 125000)

    def test_device_selector_cannot_inject_adb_arguments(self):
        for invalid in ("", "emulator-5554; command", "-s malicious", "name\ncommand"):
            with self.subTest(invalid=invalid), self.assertRaises(DeviceFailure):
                AndroidDevice(invalid)

    def test_actual_apk_package_abi_and_signature_metadata_must_agree(self):
        badging = "package: name='com.banataosystems.pandora_mobile' versionCode='21' versionName='0.4.0-rc.14'\nnative-code: 'arm64-v8a'\n"
        signing = "Verified using v2 scheme (APK Signature Scheme v2): true\nSigner #1 certificate SHA-256 digest: " + "a" * 64 + "\nSigner #1 certificate DN: CN=Android Debug"
        result = parse_package_evidence(badging, signing, "0.4.0-rc.14+21")
        self.assertEqual(result["signer_sha256"], "a" * 64)
        self.assertTrue(result["debug_signer"])
        self.assertFalse(result["production_signing_verified"])
        for altered_badging, altered_signing in (
            (badging.replace("arm64-v8a", "x86_64"), signing),
            (badging.replace("versionCode='21'", "versionCode='22'"), signing),
            (badging, signing.replace(": true", ": false")),
            (badging, signing + "\nSigner #2 certificate SHA-256 digest: " + "b" * 64),
        ):
            with self.assertRaises(DeviceFailure):
                parse_package_evidence(altered_badging, altered_signing, "0.4.0-rc.14+21")


if __name__ == "__main__":
    unittest.main()
