#!/usr/bin/env python3
"""Capture native PLP sign-in semantics without credentials or app mutations."""

import argparse
import base64
import binascii
import re
import subprocess
import sys
import time
from pathlib import Path
import xml.etree.ElementTree as ET

PACKAGE = "com.banataosystems.pandora.plp"
SCHEMA = "pandora.android.ui-capture.v1"
COMPONENT = "com.banataosystems.pandora.uicapture/.CaptureInstrumentation"


class CaptureFailure(Exception):
    """Only fixed, non-sensitive diagnostic codes may leave this process."""


def decode_capture(stdout):
    if len(stdout) > 524288:
        raise CaptureFailure("CAPTURE_TOO_LARGE")
    fields = {}
    codes = []
    for line in stdout.splitlines():
        if line.startswith("INSTRUMENTATION_RESULT: "):
            key, separator, value = line[len("INSTRUMENTATION_RESULT: "):].partition("=")
            if not separator or key in fields:
                raise CaptureFailure("CAPTURE_RESULT_INVALID")
            fields[key] = value
        elif line.startswith("INSTRUMENTATION_CODE: "):
            codes.append(line[len("INSTRUMENTATION_CODE: "):].strip())
    if codes != ["-1"] or fields.get("status") != "ok":
        raise CaptureFailure("CAPTURE_NOT_SUCCESSFUL")
    if fields.get("capture_schema") != SCHEMA:
        raise CaptureFailure("CAPTURE_SCHEMA_INVALID")
    try:
        xml = base64.b64decode(fields.get("capture_base64", ""), validate=True)
        if len(xml) > 524288 or b"<!" in xml:
            raise CaptureFailure("CAPTURE_XML_INVALID")
        root = ET.fromstring(xml)
    except (ValueError, binascii.Error, ET.ParseError):
        raise CaptureFailure("CAPTURE_XML_INVALID") from None
    if root.tag != "hierarchy" or root.attrib.get("schema") != SCHEMA:
        raise CaptureFailure("CAPTURE_SCHEMA_INVALID")
    nodes = list(root)
    if not 1 <= len(nodes) <= 512 or fields.get("node_count") != str(len(nodes)):
        raise CaptureFailure("CAPTURE_NODE_COUNT_INVALID")
    for node in nodes:
        if node.tag != "node" or list(node) or node.attrib.get("package") != PACKAGE:
            raise CaptureFailure("CAPTURE_SCOPE_INVALID")
        if is_input(node):
            if (node.attrib.get("text") or node.attrib.get("content-desc") or
                    node.attrib.get("input-value-redacted") != "true"):
                raise CaptureFailure("CAPTURE_INPUT_NOT_REDACTED")
    return xml, nodes


def is_input(node):
    return (node.attrib.get("editable") == "true" or
            node.attrib.get("password") == "true" or
            node.attrib.get("class", "").endswith("EditText"))


def verify_sign_in(nodes, phase):
    if phase not in {"sign-in", "validation", "restart"}:
        raise CaptureFailure("CAPTURE_PHASE_INVALID")
    inputs = [node for node in nodes if is_input(node)]
    if len(inputs) != 2:
        raise CaptureFailure("SIGN_IN_FIELDS_MISSING")
    fields = {}
    for label in ("Email", "Password"):
        matching = [node for node in inputs
                    if re.match(r"^" + label + r"(?:$|[\s,])", node.attrib.get("hint", ""))]
        if len(matching) != 1 or matching[0].attrib.get("enabled") != "true":
            raise CaptureFailure("SIGN_IN_NATIVE_HINT_MISSING")
        fields[label] = matching[0]
    if (fields["Email"] is fields["Password"] or
            fields["Email"].attrib.get("password") != "false" or
            fields["Password"].attrib.get("password") != "true"):
        raise CaptureFailure("SIGN_IN_PASSWORD_NOT_OBSCURED")
    if phase == "validation":
        for label, message in (("Email", "Enter your email."),
                               ("Password", "Enter your password.")):
            if message not in fields[label].attrib.get("hint", ""):
                raise CaptureFailure("EMPTY_SUBMIT_VALIDATION_MISSING")
    buttons = [node for node in nodes if not is_input(node) and
               any(node.attrib.get(key, "").strip() == "Sign in"
                   for key in ("text", "content-desc")) and
               node.attrib.get("enabled") == "true" and
               node.attrib.get("clickable") == "true"]
    if len(buttons) != 1:
        raise CaptureFailure("SIGN_IN_BUTTON_NOT_TAPPABLE")
    match = re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]",
                         buttons[0].attrib.get("bounds", ""))
    if match is None:
        raise CaptureFailure("SIGN_IN_BOUNDS_INVALID")
    x1, y1, x2, y2 = map(int, match.groups())
    if x2 <= x1 or y2 <= y1:
        raise CaptureFailure("SIGN_IN_BOUNDS_INVALID")
    return (x1 + x2) // 2, (y1 + y2) // 2


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adb", required=True)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--phase", choices=("sign-in", "validation", "restart"), required=True)
    args = parser.parse_args()
    command = [args.adb, "-s", args.serial, "shell", "am", "instrument", "-w", "-r",
               "-e", "target_package", PACKAGE, COMPONENT]
    failure = "CAPTURE_UNAVAILABLE"
    # Accessibility reconnect can precede Flutter's semantics rebuild. Retry a
    # bounded observation; all exact label/error assertions remain mandatory.
    for attempt in range(3):
        try:
            result = subprocess.run(command, capture_output=True, text=True,
                                    encoding="utf-8", timeout=20, check=False)
            if result.returncode:
                raise CaptureFailure("CAPTURE_PROCESS_FAILED")
            xml, nodes = decode_capture(result.stdout)
            args.output.parent.mkdir(parents=True, exist_ok=True)
            # Preserve the last safe native observation even if assertions fail.
            args.output.write_bytes(xml)
            x, y = verify_sign_in(nodes, args.phase)
            if args.phase == "sign-in":
                print(x, y)
            return 0
        except CaptureFailure as error:
            failure = str(error)
        except subprocess.TimeoutExpired:
            failure = "CAPTURE_TIMED_OUT"
        except (OSError, UnicodeError):
            failure = "CAPTURE_UNAVAILABLE"
        if attempt < 2:
            time.sleep(0.4)
    print(failure, file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
