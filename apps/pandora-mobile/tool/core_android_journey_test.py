"""Validate Android evidence parsing and honest stage labels, not native UX."""
import hashlib
import io
import json
import subprocess
from contextlib import redirect_stdout
from pathlib import Path
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

from core_android_device import AndroidDevice, DeviceFailure, adb_failure_receipt
from core_android_journey import Journey, bounds, semantic_snapshot, text_of, hierarchy_diagnostics

TURN = "12345678-1234-1234-1234-123456789012"
THREAD = "87654321-4321-4321-4321-210987654321"


def tree(*ids):
    root = ET.Element("hierarchy")
    for key in ids:
        ET.SubElement(root, "node", {"resource-id": key, "bounds": "[10,20][90,80]"})
    return ET.tostring(root, encoding="unicode")


class NativeEvidenceParsingTest(unittest.TestCase):
    def ime_fixture(self, observations):
        journey = Journey.__new__(Journey)
        journey.coverage = {}
        journey.ime_observations = []
        current = {"index": -1}
        def flag(**kwargs):
            current["index"] += 1
            return observations[min(current["index"], len(observations) - 1)][0]
        def geometry(**kwargs):
            return observations[min(current["index"], len(observations) - 1)][1]
        journey.android = SimpleNamespace(ime_visible=flag, ime_state=flag, window_insets=geometry)
        return journey, current

    def insets(self, frame=(0, 800, 720, 1280), visible=True):
        return {"display": (0, 0, 720, 1280), "cutout_insets": (0, 0, 0, 0), "sources": [
            {"type": "statusBars", "frame": (0, 0, 720, 48), "visible": True},
            {"type": "navigationBars", "frame": (0, 1232, 720, 1280), "visible": True},
            {"type": "ime", "frame": frame, "visible": visible},
        ]}

    def test_keyboard_waits_for_one_usable_geometry_snapshot_and_retains_first_incomplete_sample(self):
        empty, hidden, ready = self.insets(frame=(0, 0, 0, 0)), self.insets(visible=False), self.insets()
        journey, _ = self.ime_fixture([(True, empty), (True, hidden), (True, ready)])
        with patch("core_android_journey.time.sleep"):
            result = journey.wait_for_ime_geometry()
        self.assertIs(result, ready)
        evidence = journey.ime_observations[0]
        self.assertEqual(evidence["samples"], 3)
        self.assertEqual(evidence["first_incomplete"]["ime_sources"][0]["frame"], (0, 0, 0, 0))
        self.assertTrue(evidence["first_incomplete"]["input_shown"])
        self.assertFalse(evidence["first_incomplete"]["ready"])
        self.assertTrue(evidence["ready"]["ready"])
        # Containment consumes this exact source snapshot, never a second dump.
        field = ET.Element("node", {"class": "android.widget.EditText", "focused": "true", "bounds": "[20,700][700,790]"})
        root = ET.Element("hierarchy"); root.append(field)
        journey.snapshot = lambda: {"root": root}
        journey.android.window_insets = lambda: self.fail("Containment resampled ready geometry")
        journey.assert_sign_in_insets(focused_only=True, insets=result)
        self.assertTrue(journey.coverage["sign_in_ime_insets"])

    def test_ready_geometry_overlap_fails_immediately_without_polling_it_away(self):
        journey, current = self.ime_fixture([(True, self.insets())])
        ready = journey.wait_for_ime_geometry()
        root = ET.fromstring('<hierarchy><node class="android.widget.EditText" focused="true" bounds="[20,790][700,850]"/></hierarchy>')
        journey.snapshot = lambda: {"root": root}
        with self.assertRaisesRegex(DeviceFailure, "SIGN_IN_FIELD_OVERLAPS_SYSTEM_OR_IME"):
            journey.assert_sign_in_insets(focused_only=True, insets=ready)
        self.assertEqual(current["index"], 0)
        self.assertEqual(journey.coverage, {})

    def test_missing_ime_or_false_flag_cannot_pass_and_keep_original_twenty_second_budget(self):
        absent = self.insets(); absent["sources"] = absent["sources"][:2]
        for observation in ((True, absent), (True, self.insets(frame=(0, 0, 0, 0))),
                            (False, self.insets())):
            with self.subTest(observation=observation[0]):
                journey, _ = self.ime_fixture([observation])
                clock = [0.0]
                def sleep(_):
                    clock[0] += 1.0
                with patch("core_android_journey.time.monotonic", side_effect=lambda: clock[0]), \
                     patch("core_android_journey.time.sleep", side_effect=sleep):
                    with self.assertRaisesRegex(DeviceFailure, "VISIBLE_IME_GEOMETRY_UNAVAILABLE"):
                        journey.wait_for_ime_geometry()
                self.assertEqual(clock[0], 20.0)
                self.assertIsNone(journey.ime_observations[0]["ready"])
                self.assertIsNotNone(journey.ime_observations[0]["first_incomplete"])

    def test_unparseable_ime_source_is_unavailable_not_ready(self):
        journey, _ = self.ime_fixture([(True, self.insets())])
        def unavailable(**kwargs):
            raise DeviceFailure("ANDROID_INSETS_CONTROLLER_AMBIGUOUS")
        journey.android.window_insets = unavailable
        with self.assertRaisesRegex(DeviceFailure, "ANDROID_INSETS_CONTROLLER_AMBIGUOUS"):
            journey.wait_for_ime_geometry()
        self.assertIsNone(journey.ime_observations[0]["ready"])

    def test_slow_adb_ready_sample_after_deadline_is_rejected_and_each_call_gets_remaining_budget(self):
        journey, _ = self.ime_fixture([(True, self.insets())])
        clock, budgets = [0.0], []
        def flag(**kwargs):
            budgets.append(kwargs["timeout"])
            clock[0] = 12.0
            return True
        def geometry(**kwargs):
            budgets.append(kwargs["timeout"])
            clock[0] = 20.5
            return self.insets()
        journey.android.ime_state = flag
        journey.android.window_insets = geometry
        with patch("core_android_journey.time.monotonic", side_effect=lambda: clock[0]), \
             patch("core_android_journey.time.sleep"):
            with self.assertRaisesRegex(DeviceFailure, "VISIBLE_IME_GEOMETRY_UNAVAILABLE"):
                journey.wait_for_ime_geometry()
        self.assertEqual(budgets, [20.0, 8.0])
        self.assertIsNone(journey.ime_observations[0]["ready"])
        self.assertFalse(journey.ime_observations[0]["first_incomplete"]["within_deadline"])

    def test_hierarchy_classification_does_not_attribute_foreign_resource_ids_to_core(self):
        view = hierarchy_diagnostics('<hierarchy><node package="foreign" resource-id="pandora.chat.input" '
                                     'class="android.widget.EditText"/><node resource-id="android:id/aerr_close"/></hierarchy>')
        self.assertEqual(view["edit_text_count"], 1)
        self.assertEqual(view["canonical_edit_text_count"], 0)
        self.assertFalse(view["known_chat_controls"]["input"])
        self.assertTrue(view["system_error_dialog_controls"])
        self.assertFalse(view["system_anr_wait_control"])

    def test_launch_retains_single_attempt_and_existing_ninety_second_entry_predicate(self):
        journey = Journey.__new__(Journey)
        calls = []
        journey.android = SimpleNamespace(shell=lambda *args: calls.append(args) or "Status: ok\nLaunchState: COLD\n")
        journey.wait = lambda predicate, code, seconds: calls.append((code, seconds))
        journey.launch()
        self.assertEqual(len(calls), 3)
        self.assertEqual(calls[0][:2], ("am", "force-stop"))
        self.assertEqual(calls[1][:3], ("am", "start", "-W"))
        self.assertEqual(calls[2], ("APP_ENTRY_NOT_VISIBLE", 90))
        self.assertEqual(journey.launch_result["status"], "ok")

    def test_failure_diagnostics_discard_all_arbitrary_ui_titles_attributes_and_exceptions(self):
        package = "com.banataosystems.pandora_mobile"
        xml = '<hierarchy><node package="' + package + '" class="android.widget.EditText" text="secret_canary" content-desc="secret_canary" hint="secret_canary" resource-id="secret_canary"/><node resource-id="android:id/aerr_close"/><node resource-id="com.android.permissioncontroller:id/permission_allow_button"/><node package="' + package + '" resource-id="pandora.chat.input"/></hierarchy>'
        journey = Journey.__new__(Journey)
        def shell(*args, **kwargs):
            if args[:1] == ("ps",):
                return "NAME\n" + package + "\nsecret_canary"
            if args == ("dumpsys", "window", "displays"):
                return "Display: mDisplayId=0\n mCurrentFocus=Window{123abc u0 secret_canary}\n"
            if args == ("dumpsys", "activity", "activities"):
                return "mKeyguardShowing=false\nsecret_canary"
            raise RuntimeError("secret_canary")
        journey.android = SimpleNamespace(shell=shell, ime_state=lambda **kwargs: True,
                                           window_insets=lambda **kwargs: self.insets())
        journey.device = SimpleNamespace(dump_hierarchy=lambda **kwargs: xml)
        result = journey.collect_failure_diagnostics()
        self.assertNotIn("secret_canary", json.dumps(result))
        self.assertEqual(result["process"]["canonical_process_count"], 1)
        self.assertEqual(result["hierarchy"]["edit_text_count"], 1)
        self.assertTrue(result["hierarchy"]["known_chat_controls"]["input"])
        self.assertTrue(result["hierarchy"]["system_error_dialog_controls"])
        self.assertFalse(result["hierarchy"]["system_anr_wait_control"])
        self.assertEqual(result["hierarchy"]["permission_control_count"], 1)
        self.assertEqual(result["historical_exits"], {"observed": False, "acquisition": "unavailable"})
        self.assertFalse(result["window"]["canonical_error_dialog"])

    def test_diagnostic_failure_cannot_replace_original_failure_or_emit_exception_message(self):
        journey = Journey.__new__(Journey)
        journey.installed = {"apk_sha256": "a" * 64}
        journey.android = SimpleNamespace(installed_digest=lambda: "a" * 64, shell=lambda *args, **kwargs: "")
        journey.mode = "platform"
        def fail():
            raise DeviceFailure("APP_ENTRY_NOT_VISIBLE")
        def diagnostic_fail():
            raise RuntimeError("secret_canary")
        journey.platform = fail
        journey.collect_failure_diagnostics = diagnostic_fail
        written = []
        journey.write_receipt = lambda passed: written.append((passed, journey.failure, journey.failure_diagnostics))
        output = io.StringIO()
        with redirect_stdout(output):
            result = journey.run()
        self.assertEqual(result, 1)
        self.assertEqual(written, [(False, "APP_ENTRY_NOT_VISIBLE", {"observed": False, "acquisition": "unavailable"})])
        self.assertNotIn("secret_canary", output.getvalue())
        self.assertIn("APP_ENTRY_NOT_VISIBLE", output.getvalue())
        self.assertIsNone(journey.original_adb_failure)

    def test_original_checked_adb_failure_survives_unchecked_exit_and_six_failed_diagnostics(self):
        with tempfile.TemporaryDirectory() as directory:
            journey = Journey.__new__(Journey)
            journey.output = Path(directory) / "receipt.json"
            journey.installed = {"source_sha": "a" * 40, "apk_sha256": "b" * 64,
                                 "installed_apk_sha256": "b" * 64}
            journey.android = AndroidDevice("private-serial")
            journey.android.installed_digest = lambda: "b" * 64
            journey.device = SimpleNamespace(dump_hierarchy=lambda **kwargs: (_ for _ in ()).throw(RuntimeError("private-token")))
            journey.mode, journey.authenticated, journey.thread = "platform", False, None
            journey.steps, journey.timings = [{"step": n} for n in range(4)], []
            journey.started, journey.private_evidence = time.monotonic(), None
            def fail():
                journey.android.run("private-unchecked", check=False)
                journey.android.ime_state()
            journey.platform = fail
            results = [subprocess.CompletedProcess([], 2, "private-token", "error: device unauthorized."),
                       subprocess.CompletedProcess([], 7, "private-token", "error: device offline")]
            def command(*args, **kwargs):
                return results.pop(0) if results else subprocess.CompletedProcess([], 9, "private-token", "error: device unauthorized.")
            output = io.StringIO()
            with patch("core_android_device.subprocess.run", side_effect=command) as run, redirect_stdout(output):
                self.assertEqual(journey.run(), 1)
            receipt = json.loads(journey.output.read_text())
            self.assertEqual(receipt["failure_code"], "ADB_COMMAND_FAILED")
            self.assertEqual(receipt["original_adb_failure"], {
                "command_class": "read_ime_state", "failure_kind": "nonzero_exit",
                "exit_code": 7, "stderr_category": "device_offline"})
            for field in ("process", "window", "keyguard", "historical_exits", "hierarchy", "ime"):
                self.assertEqual(receipt["failure_diagnostics"][field], {"observed": False, "acquisition": "unavailable"})
            self.assertEqual(len(receipt["steps"]), 4)
            self.assertFalse(receipt["runtime_verified"])
            self.assertEqual(run.call_count, 10)  # 2 original, 5 diagnostic, 3 unchanged cleanup calls.
            for canary in ("private-token", "private-serial", "private-unchecked"):
                self.assertNotIn(canary, journey.output.read_text() + output.getvalue())

    def test_ime_timeout_retains_metadata_without_changing_failure_code_or_budget(self):
        journey, _ = self.ime_fixture([])
        journey.android = AndroidDevice("private-serial")
        error = subprocess.TimeoutExpired(["private-argument"], 20, output=b"private-token")
        with patch("core_android_device.subprocess.run", side_effect=error) as run:
            with self.assertRaisesRegex(DeviceFailure, "^VISIBLE_IME_GEOMETRY_UNAVAILABLE$") as caught:
                journey.wait_for_ime_geometry()
        self.assertEqual(adb_failure_receipt(caught.exception), {
            "command_class": "read_ime_state", "failure_kind": "timeout",
            "exit_code": None, "stderr_category": "unknown"})
        self.assertEqual(run.call_count, 1)
        self.assertGreater(run.call_args.kwargs["timeout"], 0)
        self.assertLessEqual(run.call_args.kwargs["timeout"], 20)

    def cancellation_fixture(self, states):
        journey = Journey.__new__(Journey)
        journey.coverage = {}
        journey.cancellation_outcomes = []
        observations = iter(states)
        calls = []
        def view():
            phase, acknowledgement, retry = next(observations)
            calls.append(("observe", phase, acknowledgement))
            return {"phases": {TURN: phase}, "unknown_outcomes": {TURN: acknowledgement} if acknowledgement else {},
                    "nodes": {"pandora.chat.retry." + TURN: ET.Element("node")} if retry else {}}
        def wait(predicate, code, seconds=0):
            for _ in range(8):
                try:
                    result = predicate()
                except StopIteration:
                    break
                if result:
                    return result
            raise DeviceFailure(code)
        journey.verify_thread = view
        journey.wait = wait
        journey.click = lambda key: calls.append(("click", key))
        return journey, calls

    def test_native_stop_with_confirmed_cancellation_never_acknowledges_unknown(self):
        journey, calls = self.cancellation_fixture([("cancelled", None, False)])
        self.assertEqual(journey.resolve_cancellation(TURN), "cancelled")
        self.assertFalse(any(call[0] == "click" for call in calls))
        self.assertTrue(journey.coverage["safe_cancellation"])
        self.assertFalse(journey.coverage["unknown_acknowledgement"])

    def test_native_unknown_requires_explicit_continue_and_durable_ack_before_distinct_send(self):
        journey, calls = self.cancellation_fixture([
            ("reconciling", "unacknowledged", False),
            ("acknowledgingUnknown", "unacknowledged", False),
            ("reconciling", "unacknowledged", False),
            ("reconciling", "acknowledged", False),
        ])
        self.assertEqual(journey.resolve_cancellation(TURN), "acknowledged_unknown")
        calls.append(("send-distinct",))
        self.assertEqual(calls, [
            ("observe", "reconciling", "unacknowledged"),
            ("click", "pandora.chat.continue." + TURN),
            ("observe", "acknowledgingUnknown", "unacknowledged"),
            ("observe", "reconciling", "unacknowledged"),
            ("observe", "reconciling", "acknowledged"), ("send-distinct",),
        ])
        self.assertTrue(journey.coverage["unknown_acknowledgement"])
        self.assertNotIn(TURN, json.dumps(journey.cancellation_outcomes))

    def test_native_acknowledgement_does_not_overrule_genuine_completion_race(self):
        journey, calls = self.cancellation_fixture([
            ("reconciling", "unacknowledged", False), ("completed", None, False),
        ])
        self.assertEqual(journey.resolve_cancellation(TURN), "completed")
        self.assertFalse(journey.coverage["safe_cancellation"])
        self.assertFalse(journey.coverage["unknown_acknowledgement"])

    def test_pending_ack_or_ordinary_stop_auto_ack_cannot_pass_native_case(self):
        for states, code in (
            ([("reconciling", "acknowledged", False)], "ORDINARY_STOP_ACKNOWLEDGED_UNKNOWN"),
            ([("reconciling", "unacknowledged", True)], "UNKNOWN_OUTCOME_RETRY_EXPOSED"),
            ([("reconciling", "unacknowledged", False),
              ("acknowledgingUnknown", "unacknowledged", False)], "DURABLE_UNKNOWN_ACKNOWLEDGEMENT_NOT_CONFIRMED"),
        ):
            with self.subTest(code=code):
                journey, _ = self.cancellation_fixture(states)
                with self.assertRaisesRegex(DeviceFailure, code):
                    journey.resolve_cancellation(TURN)
                self.assertEqual(journey.cancellation_outcomes, [])

    def test_unknown_acknowledgement_semantics_cannot_contradict_one_another(self):
        with self.assertRaisesRegex(DeviceFailure, "CONTRADICTORY_UNKNOWN_ACKNOWLEDGEMENT"):
            semantic_snapshot(tree("pandora.chat.outcome-unknown." + TURN + ".acknowledged",
                                   "pandora.chat.outcome-unknown." + TURN + ".unacknowledged"))

    def test_history_anchor_uses_immutable_message_not_growing_active_card(self):
        journey = Journey.__new__(Journey)
        def node(rectangle):
            return ET.Element("node", {"bounds": rectangle})
        user_key = "pandora.chat.user." + TURN
        current_key = "pandora.chat.turn." + THREAD
        view = {"phases": {TURN: "completed", THREAD: "streaming"}, "nodes": {
            "pandora.chat.input": node("[10,700][710,760]"),
            user_key: node("[20,150][500,190]"),
            current_key: node("[0,200][720,2000]"),
            "pandora.chat.response." + THREAD: node("[20,220][700,1800]"),
        }}
        journey.verify_thread = lambda: view
        self.assertEqual(journey.anchor(), (user_key, 150))
        view["nodes"][current_key] = node("[0,200][720,3000]")
        journey.node = lambda key: view["nodes"][key]
        journey.assert_anchor((user_key, 150))
        view["nodes"][user_key] = node("[20,200][500,240]")
        with self.assertRaisesRegex(DeviceFailure, "INTENTIONAL_HISTORY_POSITION_MOVED"):
            journey.assert_anchor((user_key, 150))

    def test_selector_close_requires_both_anchor_and_history_reading_intent(self):
        for keep_intent in (True, False):
            journey = Journey.__new__(Journey)
            journey.coverage = {}
            calls = []
            nodes = {"pandora.chat.stop": ET.Element("node")}
            if keep_intent:
                nodes["pandora.chat.latest"] = ET.Element("node")
            journey.snapshot = lambda: {"nodes": nodes}
            journey.click = lambda key: calls.append(key)
            journey.open_model_options = lambda: calls.append("open-options")
            journey.picker_contained = lambda: calls.append("contained")
            journey.assert_anchor = lambda reference: calls.append(reference)
            if keep_intent:
                journey.picker_anchor_roundtrip(("immutable", 150))
                self.assertTrue(journey.coverage["selector_history_anchor"])
                self.assertEqual(calls, ["open-options", "contained",
                                         "pandora.chat.model-picker.close", ("immutable", 150)])
            else:
                with self.assertRaisesRegex(DeviceFailure, "HISTORY_INTENT_LOST_AFTER_PICKER"):
                    journey.picker_anchor_roundtrip(("immutable", 150))

    def test_manual_fast_case_selects_visible_enabled_model_and_checks_after_real_send(self):
        journey = Journey.__new__(Journey)
        journey.coverage = {}
        calls = []
        def node(rectangle, enabled="true"):
            return ET.Element("node", {"bounds": rectangle, "enabled": enabled})
        surface = node("[10,100][710,900]")
        chosen = "pandora.chat.model.available-cloud"
        nodes = {
            "pandora.chat.model-picker": surface,
            "pandora.chat.model.offscreen-cloud": node("[20,1100][700,1170]"),
            "pandora.chat.model.disabled-cloud": node("[20,600][700,670]", "false"),
            "pandora.chat.model.local-device": node("[20,670][700,720]"),
            chosen: node("[20,720][700,790]"),
        }
        journey.snapshot = lambda: {"nodes": nodes}
        journey.node = lambda key: nodes[key]
        journey.click = lambda key: calls.append(("click", key))
        journey.open_model_options = lambda: calls.append(("open-options",))
        journey.selection = lambda key: calls.append(("selected", key))
        journey.reveal_picker_choice = lambda key: calls.append(("reveal", key))
        journey.picker_contained = lambda: None
        journey.send = lambda text: calls.append(("send",)) or TURN
        journey.complete = lambda turn: calls.append(("complete", turn))
        journey.manual_and_fast_selection()
        clicked = [call[1] for call in calls if call[0] == "click"]
        self.assertIn(chosen, clicked)
        self.assertNotIn("pandora.chat.model.offscreen-cloud", clicked)
        self.assertNotIn("pandora.chat.model.disabled-cloud", clicked)
        self.assertNotIn("pandora.chat.model.local-device", clicked)
        completion = calls.index(("complete", TURN))
        self.assertIn(("selected", chosen), calls[completion + 1:])
        self.assertIn(("selected", "pandora.chat.reasoning.fast"), calls[completion + 1:])
        self.assertEqual(clicked[-1], "pandora.chat.reasoning.balanced")
        self.assertTrue(journey.coverage["manual_model_selection"])
        self.assertTrue(journey.coverage["fast_reasoning"])

    def cube_menu_fixture(self, *, fault=None, initial_ime=True):
        journey = Journey.__new__(Journey)
        journey.coverage = {}
        calls = []
        state = {"surface": "none", "ime": initial_ime}
        def node(rectangle):
            return ET.Element("node", {"bounds": rectangle})
        def snapshot():
            nodes = {"pandora.chat.menu": node("[20,1150][80,1210]")}
            if state["surface"] == "menu" or (state["surface"] == "picker" and fault == "stacked"):
                nodes.update({
                    "pandora.chat.menu-surface": node("[10,500][710,1150]"),
                    "pandora.chat.menu.close": node("[660,510][700,550]"),
                    "pandora.chat.model-options": node("[20,620][700,680]"),
                    "pandora.chat.reasoning-options-entry": node("[20,680][700,740]"),
                })
                if fault == "entry-outside":
                    nodes["pandora.chat.model-options"] = node("[20,1160][700,1220]")
            if state["surface"] == "picker":
                nodes["pandora.chat.model-picker"] = node("[10,60][710,1200]")
            if state["surface"] == "none" and fault == "standalone":
                nodes["pandora.chat.model-options"] = node("[100,1150][160,1210]")
            return {"nodes": nodes}
        def click(key):
            calls.append(key)
            if key == "pandora.chat.menu":
                state.update(surface="menu", ime=fault == "menu-ime")
            else:
                self.assertIn(key, {"pandora.chat.model-options", "pandora.chat.reasoning-options-entry"})
                state.update(surface="picker", ime=fault == "picker-ime")
        def wait(predicate, code, seconds=0):
            for _ in range(3):
                if result := predicate():
                    return result
            raise DeviceFailure(code)
        insets = {"display": (0, 0, 720, 1280), "cutout_insets": (0, 0, 0, 0), "sources": [
            {"type": "statusBars", "frame": (0, 0, 720, 40), "visible": True},
            {"type": "navigationBars", "frame": (0, 1240, 720, 1280), "visible": True},
        ]}
        journey.snapshot = snapshot
        journey.click = click
        journey.wait = wait
        journey.android = SimpleNamespace(ime_visible=lambda: state["ime"], window_insets=lambda: insets)
        return journey, calls

    def test_cube_model_and_response_depth_entries_use_keyboard_safe_surface_handoff(self):
        for reasoning in (False, True):
            with self.subTest(reasoning=reasoning):
                journey, calls = self.cube_menu_fixture()
                journey.open_model_options(via_reasoning=reasoning)
                self.assertEqual(calls, ["pandora.chat.menu", "pandora.chat.reasoning-options-entry"
                                        if reasoning else "pandora.chat.model-options"])
                self.assertTrue(journey.coverage["cube_menu_dismisses_ime"])
                self.assertTrue(journey.coverage["cube_model_handoff"])
                self.assertEqual(journey.coverage.get("cube_response_depth_entry", False), reasoning)

    def test_cube_menu_or_picker_keyboard_collision_and_stacked_surfaces_cannot_pass(self):
        for fault, code in (("menu-ime", "CUBE_MENU_IME_COLLISION"),
                            ("picker-ime", "MODEL_PICKER_IME_COLLISION"),
                            ("stacked", "CUBE_MENU_AND_PICKER_OWN_VIEWPORT_TOGETHER")):
            with self.subTest(fault=fault):
                journey, calls = self.cube_menu_fixture(fault=fault)
                with self.assertRaisesRegex(DeviceFailure, code):
                    journey.open_model_options()
                self.assertEqual(journey.coverage, {})
                if fault == "menu-ime":
                    self.assertEqual(calls, ["pandora.chat.menu"])

    def test_model_action_outside_cube_surface_or_left_in_composer_is_rejected(self):
        for fault, code in (("entry-outside", "CUBE_MENU_OPTIONS_ENTRY_NOT_CONTAINED"),
                            ("standalone", "MODEL_OPTIONS_EXPOSED_OUTSIDE_CUBE_MENU")):
            with self.subTest(fault=fault):
                journey, calls = self.cube_menu_fixture(fault=fault)
                with self.assertRaisesRegex(DeviceFailure, code):
                    journey.open_model_options()
                self.assertNotIn("pandora.chat.model-options", calls)

    def test_opaque_thread_and_turn_state_are_reconstructed_without_prose(self):
        result = semantic_snapshot(tree("pandora.chat.thread." + THREAD,
                                        "pandora.chat.turn." + TURN,
                                        "pandora.chat.turn." + TURN + ".streaming"))
        self.assertEqual(result["thread"], THREAD)
        self.assertEqual(result["turns"], {TURN})
        self.assertEqual(result["phases"], {TURN: "streaming"})

    def test_conflicting_thread_phase_or_duplicate_controls_are_rejected(self):
        for ids in (
            ["pandora.chat.input", "pandora.chat.input"],
            ["pandora.chat.thread." + THREAD, "pandora.chat.thread." + TURN],
            ["pandora.chat.turn." + TURN + ".completed", "pandora.chat.turn." + TURN + ".failedRecoverably"],
        ):
            with self.subTest(ids=ids), self.assertRaises(DeviceFailure):
                semantic_snapshot(tree(*ids))

    def test_leaf_accessibility_node_is_not_treated_as_timeout(self):
        journey = Journey.__new__(Journey)
        leaf = ET.Element("node")
        self.assertIs(journey.wait(lambda: leaf, "UNREACHED", seconds=.01), leaf)

    def test_native_validation_hint_requires_explicit_observation(self):
        native = ET.fromstring('<hierarchy><node class="android.widget.EditText" '
                               'text="" content-desc="" hint="Email, Enter your email."/></hierarchy>')
        self.assertEqual(text_of(native), "")
        self.assertIn("Enter your email.", text_of(native, include_hints=True))
        missing = ET.fromstring('<hierarchy><node text="" hint="Email"/></hierarchy>')
        self.assertNotIn("Enter your email.", text_of(missing, include_hints=True))

    def test_draft_identity_binds_once_to_the_server_admitted_thread(self):
        journey = Journey.__new__(Journey)
        journey.thread = None
        journey.draft_thread = THREAD
        snapshots = iter([
            {"thread": THREAD, "phases": {}},
            {"thread": THREAD, "phases": {TURN: "pending"}},
            {"thread": TURN, "phases": {TURN: "accepted"}},
            {"thread": TURN, "phases": {TURN: "completed"}},
            {"thread": THREAD, "phases": {TURN: "accepted"}},
        ])
        journey.snapshot = lambda: next(snapshots)
        journey.verify_thread()
        journey.verify_thread()
        self.assertIsNone(journey.thread)
        journey.verify_thread()
        self.assertEqual(journey.thread, TURN)
        journey.verify_thread()
        with self.assertRaisesRegex(DeviceFailure, "ACTIVE_THREAD_CHANGED"):
            journey.verify_thread()

    def test_bounds_reject_unstructured_or_negative_values(self):
        self.assertEqual(bounds("[10,20][90,80]"), (10, 20, 90, 80))
        for value in ("arbitrary", "[-1,0][20,30]", "[1,2][3,4] suffix"):
            with self.subTest(value=value), self.assertRaises(DeviceFailure):
                bounds(value)

    def test_network_readback_uses_current_default_not_historical_validation(self):
        journey = Journey.__new__(Journey)
        for dump, expected in (
            ("Active default network: none\nHistory: network 100 VALIDATED\n", False),
            ("  Active default network: 100\n", True),
        ):
            with self.subTest(dump=dump):
                journey.android = SimpleNamespace(shell=lambda *args: dump)
                self.assertIs(journey.network_connected(), expected)
        journey.android = SimpleNamespace(shell=lambda *args: "network state unavailable")
        with self.assertRaisesRegex(DeviceFailure, "ANDROID_NETWORK_STATE_NOT_OBSERVABLE"):
            journey.network_connected()

    def test_transport_recovery_reconciles_before_exposing_same_turn_retry(self):
        journey = Journey.__new__(Journey)
        state = {"phase": "reconciling"}
        calls = []
        journey.phase = lambda turn: state["phase"]
        journey.snapshot = lambda: {"nodes": {}}
        def shell(*args):
            calls.append(args)
            return "Active default network: 100\n" if args == ("dumpsys", "connectivity") else ""
        journey.android = SimpleNamespace(shell=shell)
        def click(key):
            calls.append(("click", key))
            self.assertEqual(key, "pandora.chat.check." + TURN)
            state["phase"] = "failedRecoverably"
        journey.click = click
        journey.node = lambda key: calls.append(("node", key))
        journey.reconcile_interrupted(TURN)
        self.assertEqual(calls, [
            ("svc", "wifi", "enable"), ("svc", "data", "enable"),
            ("dumpsys", "connectivity"), ("click", "pandora.chat.check." + TURN),
            ("node", "pandora.chat.retry." + TURN),
        ])

    def test_transport_unknown_must_not_offer_unverified_retry(self):
        journey = Journey.__new__(Journey)
        journey.phase = lambda turn: "reconciling"
        journey.snapshot = lambda: {"nodes": {"pandora.chat.retry." + TURN: ET.Element("node")}}
        with self.assertRaisesRegex(DeviceFailure, "UNVERIFIED_TRANSPORT_RETRY_EXPOSED"):
            journey.reconcile_interrupted(TURN)

    def test_platform_success_cannot_be_claimed_as_chat_runtime_acceptance(self):
        with tempfile.TemporaryDirectory() as directory:
            journey = Journey.__new__(Journey)
            journey.output = Path(directory) / "receipt.json"
            journey.mode = "platform"
            journey.installed = {"source_sha": "a" * 40, "apk_sha256": "b" * 64,
                                 "installed_apk_sha256": "b" * 64}
            journey.authenticated = False
            journey.thread = THREAD
            journey.steps = []
            journey.timings = [{"turn_id": TURN, "response_sha256": "c" * 64}]
            journey.started = time.monotonic()
            journey.failure = None
            journey.private_evidence = None
            journey.android = type("Metrics", (), {"metrics": lambda self: {}})()
            journey.write_receipt(True)
            text = journey.output.read_text()
            result = json.loads(text)
            self.assertTrue(result["platform_journey_verified"])
            self.assertFalse(result["continuous_chat_journey_verified"])
            self.assertFalse(result["runtime_verified"])
            self.assertFalse(result["production_verified"])
            self.assertNotIn(TURN, text)
            self.assertNotIn(THREAD, text)
            self.assertEqual(result["thread_id_sha256"], hashlib.sha256(THREAD.encode()).hexdigest())


if __name__ == "__main__":
    unittest.main()
