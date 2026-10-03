"""Validate Android evidence parsing and honest stage labels, not native UX."""
import hashlib
import json
from pathlib import Path
import tempfile
import time
from types import SimpleNamespace
import unittest
import xml.etree.ElementTree as ET

from core_android_device import DeviceFailure
from core_android_journey import Journey, bounds, semantic_snapshot, text_of

TURN = "12345678-1234-1234-1234-123456789012"
THREAD = "87654321-4321-4321-4321-210987654321"


def tree(*ids):
    root = ET.Element("hierarchy")
    for key in ids:
        ET.SubElement(root, "node", {"resource-id": key, "bounds": "[10,20][90,80]"})
    return ET.tostring(root, encoding="unicode")


class NativeEvidenceParsingTest(unittest.TestCase):
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
