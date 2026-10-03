"""Test receipt parsing; these are not Android runtime acceptance tests."""
import unittest
from core_android_device import (AndroidDevice, DeviceFailure, parse_ime_visibility,
                                parse_metrics, parse_package_evidence,
                                parse_window_insets, require_unoccluded)


# Field layout follows pinned AOSP Android 15 dump methods. This is a parser
# fixture, not an assertion that a native device has emitted these values.
INSETS = """Display: mDisplayId=0
  WindowInsetsStateController
    InsetsState
      mDisplayFrame=Rect(0, 0 - 720, 1280)
      mDisplayCutout=DisplayCutout{insets=Rect(0, 0 - 0, 0) boundingRect={}}
        InsetsSource id=10 type=statusBars frame=[0,0][720,48] visible=true flags= sideHint=TOP
        InsetsSource id=20 type=navigationBars frame=[0,1232][720,1280] visible=true flags= sideHint=BOTTOM
        InsetsSource id=3 type=ime frame=[0,800][720,1280] visible=true flags= sideHint=BOTTOM
    Control map:
      historical-copy InsetsSource id=3 type=ime frame=[0,100][720,1280] visible=true
Display: mDisplayId=1
  WindowInsetsStateController
    InsetsState
      mDisplayFrame=Rect(0, 0 - 400, 400)
      mDisplayCutout=DisplayCutout{insets=Rect(0, 0 - 0, 0)}
        InsetsSource id=10 type=statusBars frame=[0,0][400,80] visible=true
        InsetsSource id=20 type=navigationBars frame=[0,380][400,400] visible=true
    Control map:
"""


class DeviceReceiptTest(unittest.TestCase):
    def test_insets_use_current_display_controller_not_control_map_or_other_display(self):
        insets = parse_window_insets(INSETS)
        self.assertEqual(insets["display"], (0, 0, 720, 1280))
        self.assertEqual(len(insets["sources"]), 3)
        self.assertEqual(insets["sources"][-1]["frame"], (0, 800, 720, 1280))

    def test_full_screen_containment_cannot_hide_system_bar_or_ime_overlap(self):
        insets = parse_window_insets(INSETS)
        require_unoccluded((20, 700, 700, 790), insets, "OCCLUDED")
        for rectangle in ((20, 10, 120, 55), (20, 790, 700, 840), (20, 1240, 700, 1270)):
            with self.subTest(rectangle=rectangle), self.assertRaisesRegex(DeviceFailure, "OCCLUDED"):
                require_unoccluded(rectangle, insets, "OCCLUDED")
        hidden = parse_window_insets(INSETS.replace("[0,800][720,1280] visible=true", "[0,800][720,1280] visible=false"))
        require_unoccluded((20, 850, 700, 900), hidden, "OCCLUDED")

    def test_cutout_insets_are_applied_independently_of_bar_visibility(self):
        insets = parse_window_insets(INSETS.replace("insets=Rect(0, 0 - 0, 0)", "insets=Rect(16, 0 - 0, 0)"))
        with self.assertRaisesRegex(DeviceFailure, "CUTOUT"):
            require_unoccluded((5, 200, 100, 240), insets, "CUTOUT")
        require_unoccluded((20, 200, 100, 240), insets, "CUTOUT")

    def test_missing_ambiguous_or_unparsed_geometry_fails_instead_of_using_full_screen(self):
        for altered in ("unavailable", INSETS.replace("mDisplayId=1", "mDisplayId=0"),
                        INSETS.replace("mDisplayFrame=", "unrecognized="),
                        INSETS.replace("type=navigationBars", "type=unsupported"),
                        INSETS.replace("Control map:", "unrecognized:", 1)):
            with self.subTest(altered=altered[:40]), self.assertRaises(DeviceFailure):
                parse_window_insets(altered)

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
