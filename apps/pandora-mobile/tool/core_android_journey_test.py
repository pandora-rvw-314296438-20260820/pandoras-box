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
