#!/usr/bin/env python3
"""Authenticated owner visual capture. Credentials come from the environment and are never written."""
import base64
import json
import os
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from pathlib import Path

ADB = [os.environ.get("ADB", ""), "-s", "emulator-5554"]
PKG = "com.banataosystems.pandora.plp"
COMPONENT = "com.banataosystems.pandora.uicapture/.CaptureInstrumentation"
OUT = Path(".plp-android-build/plp-owner-visual-evidence")
EMAIL = os.environ.get("PLP_OWNER_EMAIL", "")
PASSWORD = os.environ.get("PLP_OWNER_PASSWORD", "")
REASON = "Review the Pueblo La Perla customer shell"

SCREENS = (
    ("01-home", "Home"),
    ("02-needs-you", "Needs You"),
    ("03-clients", "Clients"),
    ("04-business", "Business"),
    ("05-platform", "Platform"),
    ("06-administration", "Administration"),
    ("07-activity", "Activity"),
    ("08-operations-room", "Operations Room"),
    ("09-vision", "Vision Intelligence"),
    ("10-capabilities", "Capabilities & Providers"),
    ("11-live-connections", "Live Connections"),
    ("12-saved-evidence", "Saved Evidence"),
    ("13-verify-safety", "Verify & Safety"),
)


def redact(text):
    redacted = text
    for secret in (EMAIL, PASSWORD):
        if secret:
            redacted = redacted.replace(secret, "[redacted]")
    return redacted


def log(message):
    print(redact(message), flush=True)


def adb(*args, timeout=40):
    result = subprocess.run(ADB + list(args), capture_output=True, timeout=timeout)
    if result.returncode != 0:
        err = redact(result.stderr.decode("utf-8", "replace")[-300:])
        raise RuntimeError(redact("adb failed: " + err))
    return result


def capture():
    result = adb(
        "shell", "am", "instrument", "-w", "-r",
        "-e", "target_package", PKG,
        "-e", "capture_mode", "labels",
        COMPONENT,
        timeout=25,
    )
    text = result.stdout.decode("utf-8", "replace")
    fields = {}
    for line in text.splitlines():
        if line.startswith("INSTRUMENTATION_RESULT: "):
            key, sep, value = line[len("INSTRUMENTATION_RESULT: "):].partition("=")
            if sep:
                fields[key] = value
    if fields.get("status") != "ok":
        raise RuntimeError("capture status=" + fields.get("status", "missing") + " code=" + fields.get("error_code", ""))
    xml = base64.b64decode(fields["capture_base64"], validate=True)
    return list(ET.fromstring(xml))


def capture_retry(attempts=6, delay=2):
    last = "capture unavailable"
    for _ in range(attempts):
        try:
            return capture()
        except Exception as error:
            last = redact(str(error))
            time.sleep(delay)
    raise RuntimeError(last)


def node_label(node):
    for key in ("text", "content-desc", "hint"):
        value = (node.attrib.get(key) or "").strip()
        if value:
            return value
    return ""


def labels(nodes):
    found = []
    for node in nodes:
        value = node_label(node).replace("\n", " ")
        if value:
            found.append(value[:160])
    return found


def contains_account(nodes):
    blob = "\n".join(labels(nodes))
    return bool(EMAIL and EMAIL in blob) or bool(PASSWORD and PASSWORD in blob)


def find(nodes, label, clickable=None):
    for node in nodes:
        values = [node.attrib.get(key, "") for key in ("text", "content-desc", "hint")]
        if any(value == label or value.startswith(label) for value in values):
            if clickable is None or (node.attrib.get("clickable") == "true") == clickable:
                return node
    return None


def center(node):
    match = re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", node.attrib.get("bounds", ""))
    if match is None:
        raise RuntimeError("missing bounds")
    x1, y1, x2, y2 = map(int, match.groups())
    return (x1 + x2) // 2, (y1 + y2) // 2


def tap(node):
    x, y = center(node)
    adb("shell", "input", "tap", str(x), str(y))


def paste(value):
    adb("shell", "cmd", "clipboard", "set", value)
    adb("shell", "input", "keyevent", "279")


def shot(name, nodes):
    if contains_account(nodes):
        log(name + " withheld because the frame exposed an account identifier")
        return False
    result = adb("exec-out", "screencap", "-p", timeout=30)
    png = result.stdout
    if not png.startswith(b"\x89PNG"):
        raise RuntimeError("screencap failed for " + name)
    (OUT / (name + ".png")).write_bytes(png)
    (OUT / (name + ".labels.txt")).write_text(redact("\n".join(labels(nodes))) + "\n")
    return True


def open_drawer(nodes):
    button = find(nodes, "Open navigation", clickable=True)
    if button is None:
        adb("shell", "input", "tap", "90", "180")
        time.sleep(1)
        nodes = capture_retry(3, 1)
        button = find(nodes, "Open navigation", clickable=True)
    if button is not None:
        tap(button)
        time.sleep(1)
    return capture_retry(4, 1)


def reveal(nodes, label):
    for _ in range(5):
        found = find(nodes, label, clickable=True) or find(nodes, label)
        if found is not None:
            return nodes, found
        adb("shell", "input", "swipe", "280", "1700", "280", "700", "250")
        time.sleep(0.6)
        nodes = capture_retry(3, 1)
    return nodes, None


def go(screen_id, label):
    nodes = open_drawer(capture_retry())
    nodes, target = reveal(nodes, label)
    record = {"id": screen_id, "label": label, "captured": False, "visible": labels(nodes)[:30]}
    if target is None:
        log("missing drawer label " + label)
        return record
    tap(target)
    time.sleep(1.5)
    nodes = capture_retry()
    record["visible"] = labels(nodes)[:30]
    record["captured"] = shot(screen_id, nodes)
    log(("captured " if record["captured"] else "withheld ") + screen_id)
    return record


def sign_in():
    adb("shell", "am", "force-stop", PKG)
    adb("shell", "am", "start", "-n", f"{PKG}/.MainActivity")
    nodes = None
    for _ in range(8):
        time.sleep(2)
        try:
            nodes = capture()
        except Exception as error:
            log("waiting for sign-in: " + str(error))
            continue
        email_field = find(nodes, "Email")
        sign_in = find(nodes, "Sign in", clickable=True)
        if email_field is not None and sign_in is not None:
            break
    else:
        raise RuntimeError("sign-in screen did not become ready")
    email = find(nodes, "Email")
    password = find(nodes, "Password")
    button = find(nodes, "Sign in", clickable=True)
    if email is None or password is None or button is None:
        raise RuntimeError("sign-in controls were not tappable")
    tap(email)
    time.sleep(0.3)
    paste(EMAIL)
    time.sleep(0.3)
    tap(password)
    time.sleep(0.3)
    paste(PASSWORD)
    time.sleep(0.3)
    adb("shell", "input", "keyevent", "66")
    time.sleep(2)
    deadline = time.time() + 50
    last = []
    tapped_button = False
    while time.time() < deadline:
        try:
            nodes = capture()
        except Exception as error:
            log("after submit: " + str(error))
            time.sleep(2)
            continue
        last = labels(nodes)
        blob = " | ".join(last)
        if "Sign in" not in blob and (
            "Open navigation" in blob or "Home" in blob or "Needs You" in blob
        ):
            log("left the sign-in screen")
            return nodes
        if not tapped_button and "Sign in" in blob:
            retry = find(nodes, "Sign in", clickable=True)
            if retry is not None:
                tap(retry)
                tapped_button = True
        time.sleep(3)
    log("still on an unresolved screen: " + " | ".join(last[:12]))
    raise RuntimeError("authenticated owner screen did not appear")


def enter_customer(report):
    nodes = capture_retry()
    if find(nodes, "Clients") is None and find(nodes, "Enter client workspace") is None:
        nodes = open_drawer(nodes)
        nodes, target = reveal(nodes, "Clients")
        if target is not None:
            tap(target)
            time.sleep(1.5)
            nodes = capture_retry()
    nodes, button = reveal(nodes, "Enter client workspace")
    entry = {"captured": False, "detail": "enter control not found", "visible": labels(nodes)[:30]}
    if button is None:
        report["customer_shell"] = entry
        return
    tap(button)
    time.sleep(1)
    nodes = capture_retry()
    field = find(nodes, "Reason for administrator access") or find(nodes, "For example")
    if field is None:
        entry["detail"] = "reason dialog did not appear"
        entry["visible"] = labels(nodes)[:30]
        report["customer_shell"] = entry
        return
    tap(field)
    time.sleep(0.3)
    paste(REASON)
    time.sleep(0.3)
    confirm = find(nodes, "Continue", clickable=True)
    if confirm is None:
        nodes = capture_retry()
        confirm = find(nodes, "Continue", clickable=True)
    if confirm is None:
        entry["detail"] = "continue was not tappable"
        report["customer_shell"] = entry
        return
    tap(confirm)
    deadline = time.time() + 40
    while time.time() < deadline:
        time.sleep(2)
        nodes = capture_retry()
        blob = " | ".join(labels(nodes))
        if "Return to Pandora" in blob or "Today" in blob or "Resort" in blob:
            entry["captured"] = shot("14-plp-customer", nodes)
            entry["detail"] = "customer shell visible"
            entry["visible"] = labels(nodes)[:30]
            report["customer_shell"] = entry
            back = find(nodes, "Return to Pandora", clickable=True)
            if back is None:
                nodes = open_drawer(nodes)
                back = find(nodes, "Return to Pandora", clickable=True)
            if back is not None:
                tap(back)
                time.sleep(2)
                nodes = capture_retry()
                report["returned_to_owner"] = shot("15-return-owner", nodes)
                report["return_visible"] = labels(nodes)[:30]
            else:
                report["returned_to_owner"] = False
            return
        entry["visible"] = labels(nodes)[:30]
        entry["detail"] = "customer shell not confirmed"
    report["customer_shell"] = entry
    report["returned_to_owner"] = False


def main():
    if not ADB[0] or not EMAIL or not PASSWORD:
        log("Operator sign-in environment is incomplete. Refusing to continue.")
        return 50
    OUT.mkdir(parents=True, exist_ok=True)
    adb("shell", "settings", "put", "global", "window_animation_scale", "0")
    adb("shell", "settings", "put", "global", "transition_animation_scale", "0")
    adb("shell", "settings", "put", "global", "animator_duration_scale", "0")
    report = {
        "source_sha": os.environ.get("SOURCE_SHA", ""),
        "role_gate": "installed app sign-in; server operator_mode is not mocked",
        "screens": [],
        "customer_shell": None,
        "returned_to_owner": False,
    }
    try:
        sign_in()
        for screen_id, label in SCREENS:
            report["screens"].append(go(screen_id, label))
        enter_customer(report)
    except Exception as error:
        report["error"] = redact(str(error))
        log(report["error"])
    missing = [item["id"] for item in report["screens"] if not item.get("captured")]
    report["missing_screens"] = missing
    (OUT / "report.json").write_text(redact(json.dumps(report, indent=2)) + "\n")
    expected = [screen_id for screen_id, _ in SCREENS]
    captured = {item["id"] for item in report["screens"] if item.get("captured")}
    if report.get("error") or any(screen_id not in captured for screen_id in expected):
        return 51
    if not report.get("customer_shell", {}).get("captured") or not report.get("returned_to_owner"):
        return 52
    return 0


if __name__ == "__main__":
    sys.exit(main())
