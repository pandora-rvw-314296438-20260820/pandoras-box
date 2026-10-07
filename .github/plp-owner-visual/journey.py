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
EXTRA_REDACTIONS = []
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
    for secret in (EMAIL, PASSWORD, *EXTRA_REDACTIONS):
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


def instrument(extra):
    result = adb(
        "shell", "am", "instrument", "-w", "-r",
        "-e", "target_package", PKG,
        "-e", "capture_mode", "labels",
        *extra,
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
    return fields


def screen_blob(nodes):
    return " | ".join(labels(nodes))


def sign_in_note(nodes):
    blob = screen_blob(nodes)
    notes = []
    if "Enter your email." in blob:
        notes.append("email-empty")
    if "Enter your password." in blob:
        notes.append("password-empty")
    if "Email or password is incorrect." in blob:
        notes.append("auth-rejected")
    if "Sign in" in blob:
        notes.append("sign-in-visible")
    email = find_field(nodes, "Email")
    password = find_password_field(nodes)
    if email is None:
        notes.append("email-field-missing")
    elif email.attrib.get("focused") == "true":
        notes.append("email-focused")
    if password is None:
        notes.append("password-field-missing")
    elif password.attrib.get("focused") == "true":
        notes.append("password-focused")
    return ",".join(notes) or "unrecognized"


def owner_visible(nodes):
    blob = screen_blob(nodes)
    if "invitation is needed" in blob or "Your account is ready" in blob:
        raise RuntimeError("signed in but operator workspace was not granted")
    if "Sign in" in blob:
        return False
    return "Open navigation" in blob or "Needs You" in blob or "Home" in blob


def launch_sign_in():
    adb("shell", "settings", "put", "secure", "show_ime_with_hard_keyboard", "0")
    adb("shell", "am", "force-stop", PKG)
    adb("shell", "am", "start", "-n", f"{PKG}/.MainActivity")
    for _ in range(8):
        time.sleep(2)
        try:
            nodes = capture()
        except Exception as error:
            log("waiting for sign-in: " + str(error))
            continue
        if find_field(nodes, "Email") is not None and find(nodes, "Sign in", clickable=True) is not None:
            return nodes
    raise RuntimeError("sign-in screen did not become ready")


def wait_for_owner(seconds=36):
    deadline = time.time() + seconds
    last = None
    while time.time() < deadline:
        try:
            nodes = capture()
        except Exception as error:
            log("after submit: " + str(error))
            time.sleep(2)
            continue
        last = nodes
        if owner_visible(nodes):
            log("left the sign-in screen")
            return nodes
        time.sleep(3)
    if last is not None:
        log("still on an unresolved screen: " + sign_in_note(last))
    return None


def submit_credentials(move):
    nodes = launch_sign_in()
    email = find_field(nodes, "Email")
    if email is None:
        raise RuntimeError("email field was not editable")
    tap(email)
    time.sleep(0.8)
    type_email(EMAIL)
    time.sleep(0.35)
    if move == "next":
        adb("shell", "input", "keyevent", "66")
        time.sleep(0.55)
    else:
        nodes = capture_retry(3, 1)
        password = find_password_field(nodes)
        if password is None:
            raise RuntimeError("password field was not editable")
        tap(password)
        time.sleep(0.7)
    type_secret(PASSWORD, bang="key" if move == "next" else "text")
    time.sleep(0.35)
    adb("shell", "input", "keyevent", "66")
    time.sleep(1.6)
    try:
        nodes = capture()
    except Exception as error:
        log("after submit: " + str(error))
        nodes = None
    if nodes is not None and owner_visible(nodes):
        log("left the sign-in screen")
        return nodes
    if nodes is not None:
        note = sign_in_note(nodes)
        log("after keyboard submit: " + note)
        if "auth-rejected" in note:
            return None
        if "Sign in" in screen_blob(nodes) and "email-empty" not in note and "password-empty" not in note:
            button = find(nodes, "Sign in", clickable=True)
            if button is not None:
                tap(button)
                time.sleep(1.5)
    return wait_for_owner()


def sign_in():
    nodes = submit_credentials("next")
    if nodes is not None:
        return nodes
    log("retrying sign-in by tapping the password field")
    nodes = submit_credentials("tap")
    if nodes is None:
        raise RuntimeError("authenticated owner screen did not appear")
    return nodes


def capture():
    fields = instrument(())
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


def find_field(nodes, hint):
    needle = hint.lower()
    for node in nodes:
        if node.attrib.get("editable") != "true" and node.attrib.get("password") != "true":
            continue
        blob = " ".join(
            (node.attrib.get(key) or "") for key in ("hint", "text", "content-desc")
        ).lower()
        if blob.startswith(needle):
            return node
    return None


def find_password_field(nodes):
    for node in nodes:
        if node.attrib.get("password") == "true":
            return node
    return find_field(nodes, "Password")



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
    encoded = value.replace("%", "%%").replace(" ", "%s").replace("'", "")
    adb("shell", f"input text '{encoded}'")


def type_secret(value, bang="key"):
    index = 0
    while index < len(value):
        if value[index] == "!":
            if bang == "text":
                paste("!")
            else:
                adb("shell", "input", "keycombination", "59", "8")
            index += 1
            continue
        if value[index] == "@":
            adb("shell", "input", "keyevent", "77")
            index += 1
            continue
        end = index
        while end < len(value) and value[end] not in "!@":
            end += 1
        paste(value[index:end])
        index = end


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
        found = find(nodes, label, clickable=True)
        if found is None:
            found = find(nodes, label)
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


def type_email(value):
    local, separator, domain = value.partition("@")
    paste(local)
    if separator:
        adb("shell", "input", "keyevent", "77")
        paste(domain)


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
    field = find(nodes, "Reason for administrator access")
    if field is None:
        field = find(nodes, "For example")
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
