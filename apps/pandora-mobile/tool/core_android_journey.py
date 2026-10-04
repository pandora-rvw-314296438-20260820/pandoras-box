#!/usr/bin/env python3
"""Interact with the installed core APK using Android UIAutomator and its real IME.

Platform mode verifies the native sign-in envelope only. Authenticated mode
requires a sanctioned email/password supplied in the process environment, and
fails closed when absent. No app rebuild, fake backend, JWT fabrication, session
injection, owner grant, or alternate input-method installation is performed.
Public receipts contain hashes/geometry/timings, never credentials or prose.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import logging
import os
from pathlib import Path
import re
import subprocess
import time
import uuid
import xml.etree.ElementTree as ET

from core_artifact_provenance import ANDROID_PACKAGE
from core_android_device import (AndroidDevice, DeviceFailure, adb_failure_receipt, require, require_unoccluded,
    ime_geometry_observation, parse_launch_result, parse_process_observation,
    parse_window_observation, parse_keyguard_observation, parse_historical_exit_observation)

UUID = r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}"
TURN_PHASE = re.compile(r"^pandora\.chat\.turn\.(" + UUID + r")\.([a-zA-Z]+)$")
THREAD = re.compile(r"^pandora\.chat\.thread\.(" + UUID + r")$")
TURN = re.compile(r"^pandora\.chat\.turn\.(" + UUID + r")$")
MESSAGE = re.compile(r"^pandora\.chat\.(?:user|response)\.(" + UUID + r")$")
UNKNOWN_OUTCOME = re.compile(r"^pandora\.chat\.outcome-unknown\.(" + UUID + r")\.(acknowledged|unacknowledged)$")
ACTIVE = {"pending", "accepted", "processing", "streaming", "reconciling", "acknowledgingUnknown"}
TERMINAL = {"completed", "cancelled", "failedRecoverably", "failedPermanently", "superseded"}
LEAKS = ("capability registry", "runtime evidence", "model assumption",
         "provider routing", "internal connection state")


def bounds(value: str) -> tuple[int, int, int, int]:
    match = re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", value)
    require(match is not None, "INVALID_ACCESSIBILITY_BOUNDS")
    return tuple(int(part) for part in match.groups())


def identifier(node: ET.Element) -> str:
    return node.get("resource-id", "").removeprefix(ANDROID_PACKAGE + ":id/")


def text_of(node: ET.Element, *, include_hints: bool = False) -> str:
    # The pinned native dumper exposes Flutter field validation as Android
    # hintText. Read it explicitly for sign-in checks, not as response content.
    keys = ("text", "content-desc", "hint") if include_hints else ("text", "content-desc")
    return "\n".join(value for item in node.iter() for key in keys
                     if (value := item.get(key, "")))


def semantic_snapshot(xml: str) -> dict:
    root = ET.fromstring(xml)
    ids = {}
    for item in root.iter("node"):
        key = identifier(item)
        if key.startswith("pandora.chat."):
            # Two independently rendered controls with the same identity are a
            # defect. A merged accessibility node must still be unique.
            require(key not in ids, "DUPLICATE_CHAT_SEMANTIC_ID")
            ids[key] = item
    threads = [match.group(1) for key in ids if (match := THREAD.fullmatch(key))]
    require(len(set(threads)) <= 1, "MULTIPLE_ACTIVE_THREAD_IDENTITIES")
    phases = {}
    unknown_outcomes = {}
    for key in ids:
        if match := TURN_PHASE.fullmatch(key):
            turn, phase = match.groups()
            require(turn not in phases, "MULTIPLE_PHASES_FOR_ONE_TURN")
            phases[turn] = phase
        if match := UNKNOWN_OUTCOME.fullmatch(key):
            turn, acknowledgement = match.groups()
            require(turn not in unknown_outcomes, "CONTRADICTORY_UNKNOWN_ACKNOWLEDGEMENT")
            unknown_outcomes[turn] = acknowledgement
    return {"root": root, "nodes": ids, "thread": threads[0] if threads else None,
            "turns": {m.group(1) for key in ids if (m := TURN.fullmatch(key))},
            "phases": phases, "unknown_outcomes": unknown_outcomes}


def hierarchy_diagnostics(xml: str) -> dict:
    """Count fixed native classes/IDs; never serialize arbitrary UI attributes."""
    nodes = list(ET.fromstring(xml).iter("node"))
    resources = {item.get("resource-id", "") for item in nodes}
    known = {key: any(node.get("package") == ANDROID_PACKAGE and
                     identifier(node) == "pandora.chat." + key for node in nodes)
             for key in ("input", "menu", "navigation", "model-picker", "menu-surface")}
    permission_ids = {package + ":id/" + name
        for package in ("com.android.permissioncontroller", "com.google.android.permissioncontroller")
        for name in ("permission_allow_button", "permission_allow_foreground_only_button", "permission_deny_button")}
    return {"observed": True, "node_count": len(nodes),
            "canonical_package_node_count": sum(node.get("package") == ANDROID_PACKAGE for node in nodes),
            "edit_text_count": sum(node.get("class") == "android.widget.EditText" for node in nodes),
            "canonical_edit_text_count": sum(node.get("class") == "android.widget.EditText" and
                                             node.get("package") == ANDROID_PACKAGE for node in nodes),
            "progress_bar_count": sum(node.get("class") == "android.widget.ProgressBar" for node in nodes),
            "known_chat_controls": known,
            # Shared error-dialog IDs cannot by themselves distinguish crash/ANR.
            "system_error_dialog_controls": bool(resources & {"android:id/aerr_close", "android:id/aerr_report"}),
            "system_anr_wait_control": "android:id/aerr_wait" in resources,
            "permission_control_count": len(resources & permission_ids)}


class Journey:
    def __init__(self, android: AndroidDevice, installed: dict, output: Path,
                 mode: str, private_evidence: Path | None = None):
        # UIAutomation debug transport logs include ACTION_SET_TEXT payloads.
        # Disable library logging before connecting and explicitly disable its
        # independent HTTP request printer before any login values are entered.
        logging.disable(logging.CRITICAL)
        import uiautomator2 as u2
        self.android = android
        self.device = u2.connect(android.serial)
        self.device.debug = False
        self.device.jsonrpc.setConfigurator({"waitForIdleTimeout": 0, "waitForSelectorTimeout": 0})
        self.installed = installed
        self.output = output
        self.mode = mode
        self.private_evidence = private_evidence
        self.steps = []
        self.timings = []
        self.thread = None
        self.draft_thread = None
        self.sent = {}
        self.token = "PANDORAQA" + uuid.uuid4().hex[:8].upper()
        self.fixture_only = False
        self.initial_ime = android.shell("settings", "get", "secure", "default_input_method").strip()
        self.started = time.monotonic()
        self.authenticated = False
        self.failure = None
        self.coverage = {}
        self.cancellation_outcomes = []
        self.ime_observations = []
        self.launch_result = None
        self.failure_diagnostics = None

    def snapshot(self) -> dict:
        return semantic_snapshot(self.device.dump_hierarchy(compressed=False))

    def wait(self, predicate, code: str, seconds: float = 20):
        until = time.monotonic() + seconds
        while time.monotonic() < until:
            result = predicate()
            if isinstance(result, ET.Element) or result:
                return result
            time.sleep(.2)
        raise DeviceFailure(code)

    def node(self, key: str, seconds: float = 15) -> ET.Element:
        return self.wait(lambda: self.snapshot()["nodes"].get(key), "MISSING_" + key, seconds)

    def click(self, key: str):
        item = self.node(key)
        require(item.get("enabled", "true") == "true", "DISABLED_" + key)
        left, top, right, bottom = bounds(item.get("bounds", ""))
        require(right > left and bottom > top, "UNTAPPABLE_" + key)
        self.device.click((left + right) // 2, (top + bottom) // 2)

    def exact_text(self, value: str, seconds: float = 15):
        def find():
            for node in self.snapshot()["root"].iter("node"):
                if node.get("text") == value or node.get("content-desc") == value:
                    return node
            return None
        node = self.wait(find, "EXPECTED_CONTROL_TEXT_ABSENT", seconds)
        left, top, right, bottom = bounds(node.get("bounds", ""))
        self.device.click((left + right) // 2, (top + bottom) // 2)

    def verify_thread(self):
        snapshot = self.snapshot()
        require(snapshot["thread"] is not None, "THREAD_ID_NOT_EXPOSED_TO_AUTOMATION")
        if self.thread is None:
            # An empty local conversation has no durable backend thread yet.
            # The server binds it atomically with the first admitted turn. Do
            # not confuse that legitimate one-time binding with navigation to
            # another thread, or accept a later thread change after binding.
            admitted = {"accepted", "processing", "streaming", "completed"}
            if any(phase in admitted for phase in snapshot["phases"].values()):
                self.thread = snapshot["thread"]
            elif self.draft_thread is not None:
                require(snapshot["thread"] == self.draft_thread, "DRAFT_THREAD_CHANGED_BEFORE_ADMISSION")
        else:
            require(snapshot["thread"] == self.thread, "ACTIVE_THREAD_CHANGED")
        return snapshot

    def open_keyboard(self):
        self.click("pandora.chat.input")
        insets = self.wait_for_ime_geometry()
        self.assert_composer_contained(insets=insets, ime_shown=True)

    def wait_for_ime_geometry(self):
        # Android 15 sets mInputShown at show dispatch. Require usable visible
        # geometry from one current InsetsState snapshot within the SAME 20s
        # budget, then use that snapshot for containment. These ADB/UI reads are
        # sequential observations, not an atomic system-wide screenshot.
        evidence = {"first_incomplete": None, "ready": None, "samples": 0}
        if not hasattr(self, "ime_observations"):
            self.ime_observations = []
        self.ime_observations.append(evidence)
        deadline = time.monotonic() + 20
        def remaining():
            budget = deadline - time.monotonic()
            require(budget > 0, "VISIBLE_IME_GEOMETRY_UNAVAILABLE")
            return budget
        def ready():
            shown = None
            try:
                shown = self.android.ime_state(timeout=remaining())
                insets = self.android.window_insets(timeout=remaining())
            except Exception as error:
                if evidence["first_incomplete"] is None:
                    evidence["first_incomplete"] = {"input_shown": shown, "geometry_observed": False}
                if isinstance(error, subprocess.TimeoutExpired):
                    raise DeviceFailure("VISIBLE_IME_GEOMETRY_UNAVAILABLE",
                                        adb_failure=getattr(error, "adb_failure", None)) from None
                raise
            observed = ime_geometry_observation(shown, insets)
            observed["within_deadline"] = time.monotonic() < deadline
            observed["ready"] = observed["ready"] and observed["within_deadline"]
            evidence["samples"] += 1
            if observed["ready"]:
                evidence["ready"] = observed
                return insets
            if evidence["first_incomplete"] is None:
                evidence["first_incomplete"] = observed
            return None
        return self.wait(ready, "VISIBLE_IME_GEOMETRY_UNAVAILABLE", 20)

    def close_keyboard(self):
        if self.android.ime_visible():
            self.device.press("back")
        self.wait(lambda: not self.android.ime_visible(), "HARDWARE_BACK_DID_NOT_CLOSE_IME")

    def assert_composer_contained(self, *, insets=None, ime_shown=None):
        snapshot = self.snapshot()
        if insets is None:
            insets = self.android.window_insets()
        if ime_shown is None:
            ime_shown = self.android.ime_visible()
        if ime_shown:
            require(ime_geometry_observation(ime_shown, insets)["ready"], "VISIBLE_IME_GEOMETRY_UNAVAILABLE")
        self.node("pandora.chat.input")
        for key in ("input", "send", "voice", "stop", "menu", "navigation", "latest"):
            node = snapshot["nodes"].get("pandora.chat." + key)
            if node is not None:
                require_unoccluded(bounds(node.get("bounds", "")), insets,
                                   "CHAT_CONTROL_OVERLAPS_SYSTEM_OR_IME")
        self.coverage["system_insets"] = True
        if ime_shown:
            self.coverage["ime_insets"] = True
        require(not any(item.get("text") == "Back" or item.get("content-desc") == "Back"
                        for item in snapshot["root"].iter("node")
                        if item.get("package") == ANDROID_PACKAGE),
                "UNEXPLAINED_BACK_CONTROL_VISIBLE")

    def assert_sign_in_insets(self, *, focused_only=False, insets=None):
        view = self.snapshot()
        fields = [node for node in view["root"].iter("node")
                  if node.get("class") == "android.widget.EditText"
                  and (not focused_only or node.get("focused") == "true")]
        require(len(fields) == (1 if focused_only else 2), "SIGN_IN_FOCUS_GEOMETRY_NOT_OBSERVABLE")
        if insets is None:
            insets = self.android.window_insets()
        if focused_only:
            require(ime_geometry_observation(True, insets)["ready"], "VISIBLE_IME_GEOMETRY_UNAVAILABLE")
        for field in fields:
            require_unoccluded(bounds(field.get("bounds", "")), insets,
                               "SIGN_IN_FIELD_OVERLAPS_SYSTEM_OR_IME")
        self.coverage["sign_in_system_insets"] = True
        if focused_only:
            self.coverage["sign_in_ime_insets"] = True

    def set_input(self, value: str):
        self.click("pandora.chat.input")
        # UiObject.set_text invokes Android accessibility ACTION_SET_TEXT. It
        # does not install/switch to a fake IME or bypass Flutter's text field.
        editor = self.device(className="android.widget.EditText")
        require(editor.count == 1, "COMPOSER_EDITABLE_NOT_UNIQUE")
        editor.set_text(value)

    def send(self, value: str, rapid=False, via_keyboard=False) -> str:
        before = set(self.verify_thread()["turns"]) | set(self.sent)
        self.set_input(value)
        button = self.node("pandora.chat.send")
        left, top, right, bottom = bounds(button.get("bounds", ""))
        started = time.monotonic()
        if via_keyboard:
            self.android.shell("input", "keycombination", "113", "66")
        else:
            self.device.click((left + right) // 2, (top + bottom) // 2)
        if rapid:
            self.device.click((left + right) // 2, (top + bottom) // 2)
        def accepted():
            view = self.verify_thread()
            new = view["turns"] - before
            if len(new) > 1:
                raise DeviceFailure("DUPLICATE_TURN_AFTER_SEND")
            return next(iter(new)) if new else None
        turn = self.wait(accepted, "SEND_NOT_ACKNOWLEDGED", 12)
        self.sent[turn] = {"request_sha256": hashlib.sha256(value.encode()).hexdigest(),
                           "start": started, "accepted": time.monotonic()}
        return turn

    def phase(self, turn: str):
        return self.verify_thread()["phases"].get(turn)

    def network_connected(self) -> bool:
        # ConnectivityService's active default network is current state. A
        # broad search for VALIDATED can accidentally match historical logs.
        dump = self.android.shell("dumpsys", "connectivity")
        match = re.search(r"^\s*Active default network:\s*(none|[0-9]+)\s*$", dump, re.MULTILINE)
        require(match is not None, "ANDROID_NETWORK_STATE_NOT_OBSERVABLE")
        return match.group(1) != "none"

    def reconcile_interrupted(self, turn: str):
        self.wait(lambda: self.phase(turn) == "reconciling", "TRANSPORT_UNCERTAINTY_NOT_OWNED", 120)
        require("pandora.chat.retry." + turn not in self.snapshot()["nodes"],
                "UNVERIFIED_TRANSPORT_RETRY_EXPOSED")
        self.android.shell("svc", "wifi", "enable")
        self.android.shell("svc", "data", "enable")
        self.wait(self.network_connected, "NETWORK_DID_NOT_RECOVER", 45)
        # No request is resent until the production readback proves the offline
        # attempt was not admitted. The same logical turn then becomes retryable.
        self.click("pandora.chat.check." + turn)
        self.wait(lambda: self.phase(turn) == "failedRecoverably", "RECOVERABLE_FAILURE_NOT_OWNED", 120)
        self.node("pandora.chat.retry." + turn)

    def complete(self, turn: str, seconds=150) -> str:
        first_content = None
        def terminal():
            nonlocal first_content
            view = self.verify_thread()
            response = view["nodes"].get("pandora.chat.response." + turn)
            if response is not None and text_of(response).strip() and first_content is None:
                first_content = time.monotonic()
            phase = view["phases"].get(turn)
            if phase in TERMINAL:
                return phase
            return None
        phase = self.wait(terminal, "TURN_DID_NOT_FINISH", seconds)
        require(phase == "completed", "TURN_FINISHED_" + str(phase))
        response = self.node("pandora.chat.response." + turn)
        content = text_of(response)
        require(bool(content.strip()), "COMPLETED_TURN_HAS_NO_RESPONSE")
        meta = self.sent.get(turn)
        if meta:
            end = time.monotonic()
            self.timings.append({"turn_id": turn, "request_sha256": meta["request_sha256"],
                "tap_to_visible_acceptance_ms": round((meta["accepted"] - meta["start"]) * 1000),
                "tap_to_first_observed_content_ms": round((first_content - meta["start"]) * 1000)
                    if first_content else None,
                "tap_to_observed_completion_ms": round((end - meta["start"]) * 1000),
                "response_sha256": hashlib.sha256(content.encode()).hexdigest(),
                "response_characters": len(content),
                "timing_kind": "UI observation, not provider TTFT"})
        return content

    def resolve_cancellation(self, turn: str) -> str:
        """Wait for authoritative Stop state; a click is never an acknowledgement."""
        def settled():
            view = self.verify_thread()
            phase = view["phases"].get(turn)
            if phase in {"cancelled", "completed"}:
                return phase
            acknowledgement = view.get("unknown_outcomes", {}).get(turn)
            require(acknowledgement != "acknowledged", "ORDINARY_STOP_ACKNOWLEDGED_UNKNOWN")
            if acknowledgement == "unacknowledged" and phase == "reconciling":
                require("pandora.chat.retry." + turn not in view["nodes"], "UNKNOWN_OUTCOME_RETRY_EXPOSED")
                return "unknown"
            return None
        outcome = self.wait(settled, "CANCELLATION_RECEIPT_NOT_CONFIRMED", 120)
        if outcome == "unknown":
            self.click("pandora.chat.continue." + turn)
            def acknowledged():
                view = self.verify_thread()
                phase = view["phases"].get(turn)
                require("pandora.chat.retry." + turn not in view["nodes"], "UNKNOWN_OUTCOME_RETRY_EXPOSED")
                if phase == "completed":
                    return "completed"
                if (view.get("unknown_outcomes", {}).get(turn) == "acknowledged"
                        and phase == "reconciling"):
                    return "acknowledged_unknown"
                # acknowledgingUnknown and an unchanged unacknowledged card
                # do not authorize a distinct turn, even if controls reappear.
                return None
            outcome = self.wait(acknowledged, "DURABLE_UNKNOWN_ACKNOWLEDGEMENT_NOT_CONFIRMED", 120)
        self.coverage["safe_cancellation"] = self.coverage.get("safe_cancellation", False) or outcome == "cancelled"
        self.coverage["unknown_acknowledgement"] = self.coverage.get("unknown_acknowledgement", False) or outcome == "acknowledged_unknown"
        self.cancellation_outcomes.append({"turn_id_sha256": hashlib.sha256(turn.encode()).hexdigest(),
                                           "outcome": outcome})
        return outcome

    def inspect_prior_turn(self, turn: str):
        for _ in range(9):
            view = self.verify_thread()
            if turn in view["phases"]:
                return view
            width, height = self.device.window_size()
            self.device.swipe(width // 2, height // 3, width // 2, height * 3 // 4, duration=.4)
        raise DeviceFailure("PRIOR_TURN_NOT_AVAILABLE_FOR_CANCELLATION_READBACK")

    def active_visible(self, turn: str):
        node = self.node("pandora.chat.response." + turn)
        _, top, _, bottom = bounds(node.get("bounds", ""))
        composer_top = bounds(self.node("pandora.chat.input").get("bounds", ""))[1]
        safe_top = self.android.window_insets()["display"][1]
        require(top < bottom and min(bottom, composer_top) - max(top, safe_top) >= min(24, bottom - top),
                "LATEST_RESPONSE_NOT_VISIBLE")
        require("pandora.chat.latest" not in self.snapshot()["nodes"], "LATEST_READING_INTENT_LOST")

    def selection(self, key: str):
        self.reveal_picker_choice(key)
        self.wait(lambda: self.snapshot()["nodes"].get(key) is not None
                  and self.snapshot()["nodes"][key].get("selected") == "true",
                  "SELECTION_NOT_CONFIRMED_" + key)
        prefix = "pandora.chat.reasoning." if key.startswith("pandora.chat.reasoning.") else "pandora.chat.model."
        selected = [node for identity, node in self.snapshot()["nodes"].items()
                    if identity.startswith(prefix) and node.get("selected") == "true"]
        require(len(selected) == 1, "AMBIGUOUS_SELECTION_STATE")

    def reveal_picker_choice(self, key: str):
        def visible():
            view = self.snapshot()
            item = view["nodes"].get(key)
            surface = view["nodes"].get("pandora.chat.model-picker")
            if item is None or surface is None:
                return False
            left, top, right, bottom = bounds(item.get("bounds", ""))
            sl, st, sr, sb = bounds(surface.get("bounds", ""))
            return left < right and top < bottom and sl <= (left + right) // 2 <= sr and st <= (top + bottom) // 2 <= sb
        to_top = key == "pandora.chat.model.auto" or key.startswith("pandora.chat.reasoning.")
        for toward_top in (to_top, not to_top):
            for _ in range(5):
                if visible():
                    return
                left, top, right, bottom = bounds(self.node("pandora.chat.model-picker").get("bounds", ""))
                low, high = top + (bottom - top) * 3 // 4, top + (bottom - top) // 3
                start, end = (high, low) if toward_top else (low, high)
                self.device.swipe((left + right) // 2, start, (left + right) // 2, end, duration=.3)
        require(visible(), "PICKER_SELECTION_NOT_REACHABLE")

    def picker_contained(self):
        surface = self.node("pandora.chat.model-picker")
        require(not self.android.ime_visible(), "MODEL_PICKER_IME_COLLISION")
        require_unoccluded(bounds(surface.get("bounds", "")), self.android.window_insets(),
                           "MODEL_PICKER_OVERLAPS_SYSTEM_INSETS")

    def open_model_options(self, *, via_reasoning=False):
        """Use the shared cube menu; the app owns IME dismissal and handoff."""
        menu = "pandora.chat.menu-surface"
        picker = "pandora.chat.model-picker"
        entries = {"pandora.chat.model-options", "pandora.chat.reasoning-options-entry"}
        entry = "pandora.chat.reasoning-options-entry" if via_reasoning else "pandora.chat.model-options"
        self.wait(lambda: not ({menu, picker} & self.snapshot()["nodes"].keys()),
                  "PREVIOUS_OPTIONS_SURFACE_DID_NOT_CLOSE")
        require(not (entries & self.snapshot()["nodes"].keys()), "MODEL_OPTIONS_EXPOSED_OUTSIDE_CUBE_MENU")
        ime_was_visible = self.android.ime_visible()
        self.click("pandora.chat.menu")

        def menu_ready():
            view = self.snapshot()
            require(picker not in view["nodes"], "PICKER_OPENED_BEFORE_CUBE_MENU_HANDOFF")
            surface = view["nodes"].get(menu)
            if surface is None:
                return False
            require(not self.android.ime_visible(), "CUBE_MENU_IME_COLLISION")
            rect = bounds(surface.get("bounds", ""))
            require_unoccluded(rect, self.android.window_insets(), "CUBE_MENU_OVERLAPS_SYSTEM_INSETS")
            item = view["nodes"].get(entry)
            require(item is not None, "CUBE_MENU_OPTIONS_ENTRY_MISSING")
            left, top, right, bottom = bounds(item.get("bounds", ""))
            require(rect[0] <= left < right <= rect[2] and rect[1] <= top < bottom <= rect[3],
                    "CUBE_MENU_OPTIONS_ENTRY_NOT_CONTAINED")
            return True

        self.wait(menu_ready, "CUBE_MENU_DID_NOT_OPEN_AFTER_IME_DISMISSAL")
        self.click(entry)

        def handed_off():
            view = self.snapshot()
            if picker not in view["nodes"]:
                if menu in view["nodes"]:
                    require(not self.android.ime_visible(), "CUBE_MENU_IME_COLLISION")
                return False
            require(not ({menu, "pandora.chat.menu.close"} | entries) & view["nodes"].keys(),
                    "CUBE_MENU_AND_PICKER_OWN_VIEWPORT_TOGETHER")
            require(not self.android.ime_visible(), "MODEL_PICKER_IME_COLLISION")
            require_unoccluded(bounds(view["nodes"][picker].get("bounds", "")),
                               self.android.window_insets(), "MODEL_PICKER_OVERLAPS_SYSTEM_INSETS")
            return True

        self.wait(handed_off, "CUBE_MENU_TO_PICKER_HANDOFF_NOT_CONFIRMED")
        self.coverage["cube_model_handoff"] = True
        if via_reasoning:
            self.coverage["cube_response_depth_entry"] = True
        if ime_was_visible:
            self.coverage["cube_menu_dismisses_ime"] = True

    def anchor(self):
        view = self.verify_thread()
        options = []
        composer_top = bounds(view["nodes"]["pandora.chat.input"].get("bounds", ""))[1]
        for key, node in view["nodes"].items():
            match = MESSAGE.fullmatch(key)
            if match and view["phases"].get(match.group(1)) == "completed":
                rect = bounds(node.get("bounds", ""))
                if rect[1] >= 0 and 32 < rect[3] < composer_top:
                    options.append((rect[1], key))
        require(bool(options), "READING_ANCHOR_UNAVAILABLE")
        y, key = sorted(options)[0]
        return key, y

    def assert_anchor(self, anchor, tolerance=8):
        key, y = anchor
        current = bounds(self.node(key).get("bounds", ""))[1]
        require(abs(current - y) <= tolerance, "INTENTIONAL_HISTORY_POSITION_MOVED")

    def picker_anchor_roundtrip(self, anchor):
        # The reference is an immutable completed message while the user is
        # reviewing history. Active response growth is intentionally excluded.
        require("pandora.chat.stop" in self.snapshot()["nodes"],
                "STREAM_FINISHED_BEFORE_SELECTOR_ANCHOR_CASE")
        self.open_model_options()
        self.picker_contained()
        self.click("pandora.chat.model-picker.close")
        self.assert_anchor(anchor)
        require("pandora.chat.latest" in self.snapshot()["nodes"], "HISTORY_INTENT_LOST_AFTER_PICKER")
        self.coverage["selector_history_anchor"] = True

    def manual_and_fast_selection(self):
        self.open_model_options()
        self.picker_contained()
        self.reveal_picker_choice("pandora.chat.reasoning.fast")
        self.click("pandora.chat.reasoning.fast")
        self.open_model_options()
        self.selection("pandora.chat.reasoning.fast")
        self.selection("pandora.chat.model.auto")
        self.coverage["fast_reasoning"] = True
        self.reveal_picker_choice("pandora.chat.model.advanced")
        self.click("pandora.chat.model.advanced")
        manual = None
        for _ in range(5):
            view = self.snapshot()
            left, top, right, bottom = bounds(self.node("pandora.chat.model-picker").get("bounds", ""))
            def visible_model(node):
                l, t, r, b = bounds(node.get("bounds", ""))
                return l < r and t < b and left <= (l + r) // 2 <= right and top <= (t + b) // 2 <= bottom
            candidates = [key for key, node in view["nodes"].items()
                          if key.startswith("pandora.chat.model.")
                          and key not in {"pandora.chat.model.auto", "pandora.chat.model.advanced",
                                          "pandora.chat.model.local-device"}
                          and node.get("enabled", "true") == "true"
                          and visible_model(node)]
            if candidates:
                manual = candidates[0]
                break
            self.device.swipe((left + right) // 2, top + (bottom - top) * 3 // 4,
                              (left + right) // 2, top + (bottom - top) // 3, duration=.3)
        require(manual is not None, "NO_SELECTABLE_MANUAL_MODEL_AVAILABLE_FOR_ACCEPTANCE")
        self.click(manual)
        self.open_model_options()
        self.selection(manual)
        self.selection("pandora.chat.reasoning.fast")
        self.click("pandora.chat.model-picker.close")
        turn = self.send("Reply briefly: selection confirmed.")
        self.complete(turn)
        self.open_model_options()
        self.selection(manual)
        self.selection("pandora.chat.reasoning.fast")
        self.coverage["manual_model_selection"] = True
        self.reveal_picker_choice("pandora.chat.model.auto")
        self.click("pandora.chat.model.auto")
        self.open_model_options()
        self.selection("pandora.chat.model.auto")
        self.selection("pandora.chat.reasoning.fast")
        self.click("pandora.chat.reasoning.balanced")

    def record(self, number: int | str, action: str, callback):
        started = time.monotonic()
        result = callback()
        self.steps.append({"step": number, "action": action, "passed": True,
                           "duration_ms": round((time.monotonic() - started) * 1000)})
        print(json.dumps({"step": number, "passed": True}), flush=True)
        # Only an explicitly private local directory may receive authenticated
        # pixels. Public workflow artifacts are metadata-only.
        if self.private_evidence is not None and self.fixture_only:
            self.private_evidence.mkdir(parents=True, exist_ok=True, mode=0o700)
            self.device.screenshot(str(self.private_evidence / f"step-{number}.png"))
        self.write_receipt(False)
        return result

    def launch(self):
        self.android.shell("am", "force-stop", ANDROID_PACKAGE)
        self.launch_result = None
        result = self.android.shell("am", "start", "-W", "-n", ANDROID_PACKAGE + "/.MainActivity")
        self.launch_result = parse_launch_result(result)
        self.wait(lambda: self.device(className="android.widget.EditText").exists
                  or "pandora.chat.input" in self.snapshot()["nodes"], "APP_ENTRY_NOT_VISIBLE", 90)

    def login(self):
        email = os.environ.get("PANDORA_CORE_QA_EMAIL", "")
        password = os.environ.get("PANDORA_CORE_QA_PASSWORD", "")
        require(bool(email and password), "SANCTIONED_QA_LOGIN_NOT_AVAILABLE")
        if "pandora.chat.input" not in self.snapshot()["nodes"]:
            fields = self.device(className="android.widget.EditText")
            require(fields.count == 2, "EXPECTED_NATIVE_SIGN_IN_FORM_ABSENT")
            fields[0].set_text(email)
            fields[1].set_text(password)
            if self.android.ime_visible():
                self.device.press("back")
            self.exact_text("Sign in")
            self.wait(lambda: "pandora.chat.input" in self.snapshot()["nodes"],
                      "NATIVE_AUTHENTICATION_NOT_CONFIRMED", 90)
        self.authenticated = True
        # Credential-filled screenshots/hierarchies are never persisted.

    def new_chat(self):
        if "pandora.chat.new-chat" not in self.snapshot()["nodes"]:
            if "pandora.chat.navigation" in self.snapshot()["nodes"]:
                self.click("pandora.chat.navigation")
            elif "pandora.chat.more" in self.snapshot()["nodes"]:
                self.click("pandora.chat.more")
            else:
                self.exact_text("Chat options")
        self.click("pandora.chat.new-chat")
        self.wait(lambda: self.snapshot()["thread"], "NEW_THREAD_ID_UNAVAILABLE")
        view = self.snapshot()
        require(not view["turns"], "QA_THREAD_IS_NOT_EMPTY")
        self.draft_thread = view["thread"]
        self.thread = None
        self.fixture_only = True

    def platform(self):
        self.record("platform-1", "Cold launch exact installed APK", self.launch)
        require("pandora.chat.input" not in self.snapshot()["nodes"], "PLATFORM_MODE_REQUIRES_SIGNED_OUT_DEVICE")
        self.record("platform-insets", "Native sign-in fields avoid observed system bars and cutouts", self.assert_sign_in_insets)
        self.record("platform-2", "Empty sign-in validates locally", lambda: self.exact_text("Sign in"))
        self.wait(lambda: "Enter your email." in text_of(self.snapshot()["root"], include_hints=True),
                  "EMAIL_VALIDATION_ABSENT")
        for index in range(3):
            def cycle():
                self.device(className="android.widget.EditText", instance=0).click()
                insets = self.wait_for_ime_geometry()
                self.assert_sign_in_insets(focused_only=True, insets=insets)
                self.device.press("back")
                self.wait(lambda: not self.android.ime_visible(), "NATIVE_SIGN_IN_IME_DID_NOT_CLOSE")
            self.record(f"platform-ime-{index + 1}", "Real IME open and hardware Back close", cycle)
        self.record("platform-background", "Background native app", lambda: self.device.press("home"))
        self.record("platform-resume", "Resume native app", lambda: self.android.shell(
            "am", "start", "-W", "-n", ANDROID_PACKAGE + "/.MainActivity"))
        self.record("platform-restart", "Force-stop and relaunch native sign-in", self.launch)
        self.record("platform-scale", "Native sign-in at increased text scale", lambda: self.android.shell(
            "settings", "put", "system", "font_scale", "1.3"))
        require(self.device(className="android.widget.EditText").count == 2, "SCALED_SIGN_IN_FORM_MISSING")
        self.android.shell("settings", "put", "system", "font_scale", "1.0")

    def authenticated_journey(self):
        self.record(1, "Cold launch", self.launch)
        def enter():
            self.login()
            self.new_chat()
        self.record(2, "Authenticate and open a fresh primary chat", enter)
        first = self.record(3, "Send Hi", lambda: self.send("Hi"))
        self.record(4, "Wait for first completion", lambda: self.complete(first))
        hello = self.record(5, "Send Hello", lambda: self.send("Hello"))
        short = self.record(6, "Send another short turn during/after generation", lambda: self.send("Hi"))
        self.complete(hello)
        self.complete(short)
        current = self.record(7, "Send What's up?", lambda: self.send("What's up?"))
        self.complete(current)
        self.record(8, "Same thread and distinct logical turns", self.verify_thread)
        self.record(9, "Open keyboard", self.open_keyboard)
        self.record(10, "Close keyboard with hardware Back", self.close_keyboard)
        self.record(11, "Open keyboard again", self.open_keyboard)
        message = "Please remember the code " + self.token + " for this conversation. Acknowledge briefly."
        self.record(12, "Type with conversation history present", lambda: self.set_input(message))
        current = self.record(13, "Send typed message using keyboard shortcut", lambda: self.send(message, via_keyboard=True))
        def options_with_keyboard():
            self.open_keyboard()
            self.open_model_options()
        self.record(14, "Open cube menu and Model while keyboard is visible during/after generation", options_with_keyboard)
        def selection():
            self.picker_contained()
            if self.node("pandora.chat.model.auto").get("selected") != "true":
                self.click("pandora.chat.model.auto")
                self.open_model_options()
            self.selection("pandora.chat.model.auto")
        self.record(15, "Inspect contained model surface and choose Auto", selection)
        def reasoning():
            self.click("pandora.chat.reasoning.deep")
            self.open_model_options()
            self.selection("pandora.chat.reasoning.deep")
            self.selection("pandora.chat.model.auto")
        self.record(16, "Choose Deep reasoning and confirm independent Auto preference", reasoning)
        self.record(17, "Close selector", lambda: self.click("pandora.chat.model-picker.close"))
        self.complete(current)
        self.record(18, "Latest exchange retained after selector", lambda: self.active_visible(current))
        def drawer():
            self.open_keyboard()
            self.click("pandora.chat.navigation")
            self.wait(lambda: not self.android.ime_visible(), "DRAWER_IME_COLLISION")
        self.record(19, "Open navigation while keyboard is visible", drawer)
        self.record(20, "Close drawer with hardware Back", lambda: self.device.press("back"))
        self.record(21, "Return to primary chat", lambda: self.node("pandora.chat.input"))
        self.record(22, "Confirm unchanged active thread", self.verify_thread)
        def interrupted():
            self.android.shell("svc", "wifi", "disable")
            self.android.shell("svc", "data", "disable")
            self.wait(lambda: not self.network_connected(), "DEVICE_NETWORK_DID_NOT_DISCONNECT", 30)
            return self.send("Reply in one short sentence after the temporary connection interruption.")
        failed = self.record(23, "Safe device network interruption for one intelligence turn", interrupted)
        self.record(24, "Reconnect and reconcile exact turn before allowing retry",
                    lambda: self.reconcile_interrupted(failed))
        self.record(25, "Retry the verified unadmitted logical turn", lambda: self.click("pandora.chat.retry." + failed))
        def recovered():
            self.complete(failed)
            require("pandora.chat.retry." + failed not in self.snapshot()["nodes"], "STALE_RETRY_AFTER_SUCCESS")
        self.record(26, "Recovery resolves failure UI", recovered)
        current = self.record(27, "Ask What can you do for me?", lambda: self.send("What can you do for me?"))
        answer = self.complete(current)
        self.record(28, "Ordinary answer excludes internal registry narration", lambda: require(
            not any(phrase in answer.lower() for phrase in LEAKS), "INTERNAL_RUNTIME_PROSE_LEAK"))
        self.record(29, "Open keyboard while latest response is visible", self.open_keyboard)
        self.record(30, "Check latest exchange remains anchored", lambda: self.active_visible(current))
        long_turn = self.send("Explain how to plan a small weekend garden in about 400 words, with practical steps.")
        self.close_keyboard()
        def review_history():
            self.wait(lambda: self.phase(long_turn) == "streaming",
                      "NATIVE_STREAM_NOT_OBSERVED_FOR_HISTORY_RACE", 120)
            width, height = self.device.window_size()
            self.device.swipe(width // 2, height // 3, width // 2, height * 3 // 4, duration=.4)
            self.node("pandora.chat.latest")
            return self.anchor()
        anchor = self.record(31, "Intentionally scroll upward into history", review_history)
        self.record("31-picker-anchor", "Open and close selector while streaming respects immutable history anchor",
                    lambda: self.picker_anchor_roundtrip(anchor))
        # The off-screen response may correctly be absent from Android's
        # accessibility tree. Observe the persistent stop control ending here,
        # then inspect the completed turn only after explicitly returning.
        self.record(32, "Receive additional content while reviewing history", lambda: self.wait(
            lambda: "pandora.chat.stop" not in self.snapshot()["nodes"],
            "HISTORY_VIEW_GENERATION_DID_NOT_FINISH", 150))
        self.record(33, "History anchor is respected", lambda: self.assert_anchor(anchor))
        self.record(34, "Explicitly return to latest", lambda: self.click("pandora.chat.latest"))
        self.complete(long_turn)
        def continue_context():
            turn = self.send("What was the code I asked you to remember earlier? Reply only with that code.")
            require(self.token in self.complete(turn), "CONVERSATION_HISTORY_NOT_RECONSTRUCTED")
            return turn
        current = self.record(35, "Continue with explicit context recall", continue_context)
        self.record(36, "Background app", lambda: self.device.press("home"))
        self.record(37, "Resume app", lambda: self.android.shell(
            "am", "start", "-W", "-n", ANDROID_PACKAGE + "/.MainActivity"))
        self.record(38, "Verify coherent resumed thread", self.verify_thread)
        def more_turns():
            for prompt in ("Thanks.", "Give me one useful next step.", "Keep it concise."):
                self.complete(self.send(prompt))
        self.record(39, "Repeat turns without resetting state", more_turns)
        self.additional_cases()

    def additional_cases(self):
        def empty():
            known = set(self.sent) | self.verify_thread()["turns"]
            self.set_input("")
            self.android.shell("input", "keycombination", "113", "66")
            time.sleep(.5)
            require(not (self.verify_thread()["turns"] - known), "EMPTY_MESSAGE_CREATED_A_TURN")
        self.record("additional-empty", "Empty keyboard submission creates no turn", empty)
        self.record("additional-rapid", "Rapid send remains one logical turn", lambda: self.complete(
            self.send("Reply with one word: acknowledged.", rapid=True)))
        self.record("additional-multiline", "Long multiline input", lambda: self.complete(self.send(
            "Summarize these notes in two sentences:\n" + "A calm and continuous conversation. " * 24)))
        def cancel_then_send():
            turn = self.send("Write a detailed explanation of urban gardening, around 600 words.")
            self.wait(lambda: self.phase(turn) in {"processing", "streaming"},
                      "CANCELLATION_ACTIVE_GENERATION_NOT_OBSERVED", 120)
            self.click("pandora.chat.stop")
            outcome = self.resolve_cancellation(turn)
            next_turn = self.send("Reply only: continued.")
            self.complete(next_turn)
            view = self.inspect_prior_turn(turn)
            phase = view["phases"][turn]
            if outcome == "cancelled":
                require(phase == "cancelled", "STALE_GENERATION_REPAINTED_CANCELLED_TURN")
            elif outcome == "acknowledged_unknown":
                require(phase == "completed" or (phase == "reconciling" and
                        view.get("unknown_outcomes", {}).get(turn) == "acknowledged"),
                        "ACKNOWLEDGED_OUTCOME_REOPENED_WITHOUT_EVIDENCE")
                require("pandora.chat.retry." + turn not in view["nodes"], "UNKNOWN_OUTCOME_RETRY_EXPOSED")
            else:
                require(phase == "completed", "AUTHORITATIVE_COMPLETION_REGRESSED")
            if "pandora.chat.latest" in self.snapshot()["nodes"]:
                self.click("pandora.chat.latest")
        self.record("additional-cancel", "Stop, resolve or explicitly acknowledge outcome, then send a distinct message", cancel_then_send)
        def repeated_picker():
            for index in range(3):
                self.open_model_options(via_reasoning=index == 1)
                self.picker_contained()
                self.click("pandora.chat.reasoning.balanced")
                self.open_model_options()
                self.selection("pandora.chat.reasoning.balanced")
                self.click("pandora.chat.model-picker.close")
                self.verify_thread()
        self.record("additional-picker", "Repeated options surface open/close", repeated_picker)
        self.record("additional-manual-fast", "Manual model preference persists through a real turn and stays independent of Fast reasoning",
                    self.manual_and_fast_selection)
        def restart():
            self.launch()
            # Android deliberately keeps its Auth session in memory. Real
            # re-authentication, followed by history restoration, is expected.
            self.login()
            self.verify_thread()
            recalled = self.complete(self.send("Repeat the code I asked you to remember earlier."))
            require(self.token in recalled, "RESTART_HISTORY_NOT_RESTORED")
        self.record("additional-restart", "Restart, re-authenticate, restore same conversation", restart)

    def collect_failure_diagnostics(self):
        # Best effort only: a missing/failed diagnostic never changes the
        # original failure or supplies false evidence of absence. No raw dump,
        # exception message, hierarchy text, logcat, or screenshot is persisted.
        def observe(callback):
            try:
                return callback()
            except Exception:
                return {"observed": False, "acquisition": "unavailable"}
        shell = lambda *args: self.android.shell(*args, timeout=8)
        return {"schema": "pandora-core-native-failure-diagnostics-v1",
            "launch": getattr(self, "launch_result", None),
            "process": observe(lambda: parse_process_observation(shell("ps", "-A", "-o", "NAME"))),
            "window": observe(lambda: parse_window_observation(shell("dumpsys", "window", "displays"))),
            "keyguard": observe(lambda: parse_keyguard_observation(shell("dumpsys", "activity", "activities"))),
            "historical_exits": observe(lambda: parse_historical_exit_observation(
                shell("dumpsys", "activity", "exit-info", ANDROID_PACKAGE))),
            "hierarchy": observe(lambda: hierarchy_diagnostics(self.device.dump_hierarchy(compressed=False))),
            "ime": observe(lambda: ime_geometry_observation(self.android.ime_state(timeout=8),
                                                            self.android.window_insets(timeout=8))),
            "scope": "sequential_failure_observations_not_atomic_or_causal_proof"}

    def write_receipt(self, passed: bool):
        self.output.parent.mkdir(parents=True, exist_ok=True)
        result = {"schema": "pandora-core-android-journey-v1", "mode": self.mode,
            "source_sha": self.installed["source_sha"], "apk_sha256": self.installed["apk_sha256"],
            "installed_apk_sha256": self.installed["installed_apk_sha256"],
            "installed": True, "authenticated": self.authenticated,
            "thread_id_sha256": hashlib.sha256(self.thread.encode()).hexdigest() if self.thread else None,
            "steps": self.steps,
            "turn_timings": [{**{key: value for key, value in timing.items() if key != "turn_id"},
                              "turn_id_sha256": hashlib.sha256(timing["turn_id"].encode()).hexdigest()}
                             for timing in self.timings],
            "duration_seconds": round(time.monotonic() - self.started, 2),
            "platform_journey_verified": passed and self.mode == "platform",
            "continuous_chat_journey_verified": passed and self.mode == "authenticated",
            "runtime_verified": passed and self.mode == "authenticated",
            "production_verified": False,
            "failure_code": self.failure,
            "original_adb_failure": getattr(self, "original_adb_failure", None),
            "safe_failure_path": "device network interruption; provider outage not asserted"
                if any(step["step"] == 23 for step in self.steps) else "not exercised",
            "physical_device_verified": False,
            "provider_timings_verified": False,
            "visual_recording": "private local evidence only" if self.private_evidence else "not captured",
            "raw_conversation_content_included": False,
            "native_case_coverage": getattr(self, "coverage", {}),
            "cancellation_outcomes": getattr(self, "cancellation_outcomes", []),
            "ime_geometry_observations": getattr(self, "ime_observations", []),
            "failure_diagnostics": getattr(self, "failure_diagnostics", None),
            "not_exercised": ["native voice/send switching", "physical device", "provider outage",
                              "provider stage timings", "private visual/video review"],
        }
        if passed:
            result["performance"] = self.android.metrics()
        self.output.write_text(json.dumps(result, indent=2) + "\n")

    def run(self) -> int:
        try:
            require(self.android.installed_digest() == self.installed["apk_sha256"],
                    "INSTALLED_APK_CHANGED_BEFORE_JOURNEY")
            if self.mode == "authenticated":
                require(bool(os.environ.get("PANDORA_CORE_QA_EMAIL")
                             and os.environ.get("PANDORA_CORE_QA_PASSWORD")),
                        "SANCTIONED_QA_LOGIN_NOT_AVAILABLE")
                self.authenticated_journey()
            else:
                self.platform()
            require(self.android.shell("settings", "get", "secure", "default_input_method").strip()
                    == self.initial_ime, "INPUT_METHOD_CHANGED_DURING_JOURNEY")
            require(self.android.installed_digest() == self.installed["apk_sha256"],
                    "INSTALLED_APK_CHANGED_DURING_JOURNEY")
            self.write_receipt(True)
            return 0
        except Exception as error:
            # Bind the original exception before best-effort ADB diagnostics.
            # Later failures and expected check=False exits cannot replace it.
            self.original_adb_failure = adb_failure_receipt(error)
            # Driver exception details can contain UI text. Only reviewed
            # failure codes/type names belong in the public receipt/log.
            self.failure = re.sub(UUID, "<turn-id>", str(error)) if isinstance(error, DeviceFailure) else type(error).__name__
            try:
                self.failure_diagnostics = self.collect_failure_diagnostics()
            except Exception:
                self.failure_diagnostics = {"observed": False, "acquisition": "unavailable"}
            self.write_receipt(False)
            print(json.dumps({"runtime_verified": False, "failure_code": self.failure}), flush=True)
            return 1
        finally:
            self.android.shell("svc", "wifi", "enable", check=False)
            self.android.shell("svc", "data", "enable", check=False)
            self.android.shell("settings", "put", "system", "font_scale", "1.0", check=False)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", default="emulator-5554")
    parser.add_argument("--adb", default="adb")
    parser.add_argument("--installed-receipt", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--mode", choices=["platform", "authenticated"], required=True)
    parser.add_argument("--private-evidence", type=Path)
    args = parser.parse_args()
    require(not (os.environ.get("GITHUB_ACTIONS") and args.private_evidence),
            "AUTHENTICATED_PIXELS_MUST_NOT_ENTER_PUBLIC_WORKFLOW_ARTIFACTS")
    installed = json.loads(args.installed_receipt.read_text())
    require(installed.get("installed") is True, "INSTALLED_ARTIFACT_RECEIPT_REQUIRED")
    return Journey(AndroidDevice(args.serial, args.adb), installed, args.output,
                   args.mode, args.private_evidence).run()


if __name__ == "__main__":
    raise SystemExit(main())
