"""Test receipt parsing; these are not Android runtime acceptance tests."""
import unittest
import json
from core_android_device import (AndroidDevice, DeviceFailure, parse_ime_visibility,
                                parse_metrics, parse_package_evidence,
                                parse_window_insets, require_unoccluded,
                                parse_ime_state,
                                ime_geometry_observation, parse_launch_result,
                                parse_process_observation, parse_window_observation,
                                parse_keyguard_observation, parse_historical_exit_observation)


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

    def test_ime_dispatch_flag_is_not_inferred_from_show_request(self):
        self.assertFalse(parse_ime_visibility("mInputShown=false imeVisible=true"))
        self.assertTrue(parse_ime_visibility("mInputShown=true"))
        self.assertFalse(parse_ime_visibility("mShowRequested=true"))
        self.assertIsNone(parse_ime_state("mShowRequested=true"))
        self.assertIsNone(parse_ime_state("mInputShown=false mInputShown=true"))
        self.assertIsNone(parse_ime_state("mInputShown=unsupported"))

    def test_real_device_cannot_report_unobserved_or_ambiguous_keyboard_as_closed(self):
        device = AndroidDevice("emulator-5554")
        for dump in ("unsupported", "mInputShown=false mInputShown=true", "mShowRequested=false"):
            device.shell = lambda *args, **kwargs: dump
            with self.assertRaisesRegex(DeviceFailure, "ANDROID_IME_VISIBILITY_NOT_OBSERVABLE"):
                device.ime_visible()
        device.shell = lambda *args, **kwargs: "mInputShown=false"
        self.assertFalse(device.ime_visible())
        device.shell = lambda *args, **kwargs: "mInputShown=true"
        self.assertTrue(device.ime_visible())

    def test_ime_dispatch_flag_requires_visible_usable_current_source(self):
        ready = parse_window_insets(INSETS)
        self.assertTrue(ime_geometry_observation(True, ready)["ready"])
        self.assertFalse(ime_geometry_observation(False, ready)["ready"])
        for altered in (
            INSETS.replace("type=ime", "type=unknown"),
            INSETS.replace("[0,800][720,1280] visible=true", "[0,800][720,1280] visible=false"),
            INSETS.replace("[0,800][720,1280]", "[0,0][0,0]"),
            INSETS.replace("[0,800][720,1280]", "[0,1280][720,800]"),
            INSETS.replace("[0,800][720,1280]", "[0,800][900,1280]"),
        ):
            with self.subTest(altered=altered[-30:]):
                self.assertFalse(ime_geometry_observation(True, parse_window_insets(altered))["ready"])

    def test_launch_diagnostics_allowlist_fields_and_reject_duplicates(self):
        package = "com.banataosystems.pandora_mobile"
        for component in ("/.MainActivity", "/" + package + ".MainActivity"):
            result = parse_launch_result("Status: ok\nLaunchState: COLD\nActivity: " + package + component +
                                         "\nTotalTime: 27531\nWaitTime: 27581\nComplete\nsecret_canary")
            self.assertTrue(result["canonical_activity"])
            self.assertEqual(result["total_time_ms"], 27531)
            self.assertEqual(result["wait_time_ms"], 27581)
            self.assertNotIn("secret_canary", json.dumps(result))
        duplicate = parse_launch_result("Status: ok\nStatus: timeout\nTotalTime: 1\nTotalTime: 2\nWaitTime: secret_canary")
        self.assertIsNone(duplicate["status"])
        self.assertIsNone(duplicate["total_time_ms"])
        self.assertIsNone(duplicate["wait_time_ms"])
        self.assertIsNone(duplicate["canonical_activity"])
        self.assertFalse(parse_launch_result("Activity: " + package + ".impostor/.MainActivity")["canonical_activity"])
        self.assertIsNone(parse_launch_result("Activity:\nTotalTime: 10")["canonical_activity"])

    def test_process_and_keyguard_missing_observations_are_unknown(self):
        self.assertIsNone(parse_process_observation("permission denied secret_canary")["canonical_process_count"])
        self.assertEqual(parse_process_observation("NAME\ncom.banataosystems.pandora_mobile\nprivate_canary")["canonical_process_count"], 1)
        self.assertEqual(parse_process_observation("NAME\ncom.banataosystems.pandora_mobile.impostor")["canonical_process_count"], 0)
        guards = parse_keyguard_observation("mKeyguardShowing=false\nmAodShowing=true\nmKeyguardGoingAway=false")
        self.assertEqual(guards, {"mKeyguardShowing": False, "mAodShowing": True, "mKeyguardGoingAway": False})
        self.assertIsNone(parse_keyguard_observation("mKeyguardShowing=true\nmKeyguardShowing=false")["mKeyguardShowing"])
        self.assertTrue(all(value is None for value in parse_keyguard_observation("secret_canary").values()))

    def test_window_focus_classification_is_exact_and_scoped_to_default_display(self):
        package = "com.banataosystems.pandora_mobile"
        def dump(title):
            return "Display: mDisplayId=0\n mCurrentFocus=Window{123abc u0 " + title + "}\nDisplay: mDisplayId=1\n mCurrentFocus=Window{123abc u0 private_canary}\n"
        self.assertEqual(parse_window_observation(dump(package + "/.MainActivity"))["focus"], "canonical_activity")
        self.assertTrue(parse_window_observation(dump("Application Error: " + package))["canonical_error_dialog"])
        self.assertTrue(parse_window_observation(dump("Application Not Responding: " + package))["canonical_anr_dialog"])
        for title in ("Application Error: " + package + ".impostor", "Application Not Responding: private_canary", package + ".impostor/.MainActivity"):
            observed = parse_window_observation(dump(title))
            self.assertFalse(observed["canonical_error_dialog"])
            self.assertFalse(observed["canonical_anr_dialog"])
            self.assertNotIn("private_canary", json.dumps(observed))
        self.assertEqual(parse_window_observation("Display: mDisplayId=0\n mCurrentFocus=null")["focus"], "none")
        for invalid in ("unavailable", dump(package).replace("mDisplayId=1", "mDisplayId=0"),
                        dump(package).replace("mCurrentFocus=", "unrecognized=")):
            self.assertEqual(parse_window_observation(invalid)["focus"], "unobserved")

    def test_normal_and_exiting_window_titles_preserve_exact_dialog_owner(self):
        package = "com.banataosystems.pandora_mobile"
        owners = ((package, "canonical_main_process"),
                  (package + ":worker", "canonical_auxiliary_process"),
                  (package + ".impostor", "other_process"),
                  ("com.android.systemui", "system_ui_process"),
                  ("com.android.systemui.impostor", "other_process"),
                  ("com.android.systemui:screenshot", "other_process"),
                  ("private_canary", "other_process"))
        for prefix, kind, field in (("Application Error: ", "application_error", "canonical_error_dialog"),
                                    ("Application Not Responding: ", "application_anr", "canonical_anr_dialog")):
            for owner, expected in owners:
                for exiting in (False, True):
                    with self.subTest(kind=kind, owner=expected, exiting=exiting):
                        title = prefix + owner + (" EXITING" if exiting else "")
                        result = parse_window_observation("Display: mDisplayId=0\n mCurrentFocus=Window{123abc u0 " + title + "}")
                        self.assertEqual(result["dialog_kind"], kind)
                        self.assertEqual(result["dialog_owner"], expected)
                        self.assertEqual(result[field], expected == "canonical_main_process")
                        self.assertEqual(result["window_exit_suffix_observed"], exiting)
                        self.assertNotIn("canary", json.dumps(result))
                        self.assertNotIn(package, json.dumps(result))

    def test_exiting_activity_classification_is_separate_from_dialog_classification(self):
        package = "com.banataosystems.pandora_mobile"
        for title in (package + "/.MainActivity", package + "/" + package + ".MainActivity"):
            result = parse_window_observation("Display: mDisplayId=0\n mCurrentFocus=Window{123abc u0 " + title + " EXITING}")
            self.assertEqual(result["focus"], "canonical_activity")
            self.assertTrue(result["window_exit_suffix_observed"])
            self.assertEqual(result["dialog_kind"], "none")
            self.assertEqual(result["dialog_owner"], "none")
            self.assertFalse(result["canonical_error_dialog"])
            self.assertFalse(result["canonical_anr_dialog"])

    def test_unknown_focus_remains_distinct_from_observed_no_dialog(self):
        for dump in ("unavailable", "Display: mDisplayId=0\n mCurrentFocus=Window{malformed}",
                     "Display: mDisplayId=0\n mCurrentFocus=null\n mCurrentFocus=null",
                     "Display: mDisplayId=0\n mCurrentFocus=null\nDisplay: mDisplayId=0\n mCurrentFocus=null"):
            result = parse_window_observation(dump)
            self.assertEqual(result["focus"], "unobserved")
            self.assertEqual(result["dialog_kind"], "unobserved")
            self.assertEqual(result["dialog_owner"], "unobserved")
            self.assertIsNone(result["window_exit_suffix_observed"])
            self.assertIsNone(result["canonical_anr_dialog"])
        for focus in ("null", "Window{abc u0 private_canary}"):
            result = parse_window_observation("Display: mDisplayId=0\n mCurrentFocus=" + focus)
            self.assertEqual(result["dialog_kind"], "none")
            self.assertEqual(result["dialog_owner"], "none")
            self.assertFalse(result["window_exit_suffix_observed"])
            self.assertFalse(result["canonical_anr_dialog"])
            self.assertNotIn("canary", json.dumps(result))

    def test_malformed_dialog_owner_is_unobserved_and_suffix_normalization_is_exact(self):
        package = "com.banataosystems.pandora_mobile"
        for owner in (" " + package, package + " EXITING EXITING", package + " EXITING private_canary",
                      package + " EXITING_EXTRA", "", "private canary", package + ":"):
            title = "Application Not Responding: " + owner
            result = parse_window_observation("Display: mDisplayId=0\n mCurrentFocus=Window{abc u0 " + title + "}")
            self.assertEqual(result["dialog_kind"], "application_anr")
            self.assertEqual(result["dialog_owner"], "unobserved")
            self.assertIsNone(result["canonical_anr_dialog"])
            self.assertFalse(result["canonical_error_dialog"])
            self.assertNotIn("canary", json.dumps(result))
            self.assertNotIn(package, json.dumps(result))
        result = parse_window_observation("Display: mDisplayId=0\n mCurrentFocus=Window{abc u0 Application Error:" + package + "}")
        self.assertEqual(result["dialog_kind"], "application_error")
        self.assertEqual(result["dialog_owner"], "unobserved")
        self.assertIsNone(result["canonical_error_dialog"])

    def test_exit_classifications_cannot_mix_processes_or_blame_historical_force_stop_on_launch(self):
        package = "com.banataosystems.pandora_mobile"
        source = ("ApplicationExitInfo #0:\n timestamp=2026-10-03 12:00:00 pid=123 realUid=1000\n process=private_canary reason=4 (CRASH) subreason=0\n"
                  "ApplicationExitInfo #1:\n timestamp=2026-10-03 12:00:00 pid=124 realUid=1000\n process=" + package + " reason=10 (USER REQUESTED) subreason=0\n"
                  " description=credential_canary\n process=" + package + " reason=5 (CRASH NATIVE) subreason=0\n"
                  "ApplicationExitInfo #2:\n timestamp=2026-10-03 12:00:00 pid=125 realUid=1000\n process=" + package + ".impostor reason=5 (CRASH NATIVE) subreason=0")
        result = parse_historical_exit_observation(source)
        self.assertEqual(result["recognized_record_count"], 1)
        self.assertEqual(result["reason_counts"]["user_requested"], 1)
        self.assertEqual(result["reason_counts"]["java_crash"], 0)
        self.assertEqual(result["reason_counts"]["native_crash"], 0)
        self.assertFalse(result["current_launch_cause_established"])
        self.assertNotIn("canary", json.dumps(result))
        for missing in ("", "permission denied private_canary", "process=" + package + " reason=4 (CRASH) subreason=0"):
            unknown = parse_historical_exit_observation(missing)
            self.assertFalse(unknown["observed"])
            self.assertIsNone(unknown["reason_counts"])
            self.assertIsNone(unknown["recognized_record_count"])

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
