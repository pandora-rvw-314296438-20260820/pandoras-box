#!/usr/bin/env python3
"""Observe a stable, drawn PLP window before installed-app input; never mutate it."""

import argparse
import hashlib
import json
import re
import subprocess
import sys
import time
from pathlib import Path

PACKAGE = "com.banataosystems.pandora.plp"
SCHEMA = "pandora.android.drawn-readiness.v1"
COMPONENT = re.compile(r"(?<![\w.])" + re.escape(PACKAGE) +
                       r"/(?:\.MainActivity|" + re.escape(PACKAGE) +
                       r"\.MainActivity)(?=[\s}]|$)")
HISTORY = re.compile(r"^(\s*)\* Hist\s+#\d+:\s*(ActivityRecord\{[^\n]*\})")
REQUIRED_TRUE = ("mVisibleRequested", "mVisible", "mClientVisible",
                 "reportedVisible", "reportedDrawn", "allDrawn", "firstWindowDrawn")


class ReadinessFailure(Exception):
    """Only fixed codes may appear in retained diagnostics."""


def value(block, name):
    values = re.findall(r"(?<![\w])" + re.escape(name) + r"=([^\s]+)", block)
    return values[0].rstrip(")") if len(values) == 1 else (None if not values else "AMBIGUOUS")


def observe_dump(text):
    if len(text) > 2097152:
        raise ReadinessFailure("ACTIVITY_READ_TOO_LARGE")
    lines = text.splitlines()
    targets = []
    for index, line in enumerate(lines):
        header = HISTORY.match(line)
        if not header or not COMPONENT.search(header.group(2)):
            continue
        indentation = len(header.group(1))
        end = index + 1
        while end < len(lines):
            following = lines[end]
            if following.strip() and len(following) - len(following.lstrip()) <= indentation:
                break
            end += 1
        targets.append((header.group(2), "\n".join(lines[index + 1:end])))
    flags = {name: None for name in REQUIRED_TRUE}
    flags.update(resumed=False, focused=False, focused_app=False,
                 exact_component=False, not_finishing=False, no_starting_surface=False)
    identity = None
    if len(targets) == 1:
        header, block = targets[0]
        identity = hashlib.sha256(header.encode("utf-8")).hexdigest()
        for name in REQUIRED_TRUE:
            item = value(block, name)
            flags[name] = item == "true" if item in {"true", "false"} else None
        flags["resumed"] = value(block, "state") == "RESUMED"
        flags["not_finishing"] = value(block, "finishing") == "false"
        flags["exact_component"] = (
            value(block, "packageName") == PACKAGE and
            COMPONENT.fullmatch(value(block, "mActivityComponent") or "") is not None)
        flags["no_starting_surface"] = (
            value(block, "startingData") == "null" and
            all(value(block, key) in {None, "null"}
                for key in ("startingWindow", "startingSurface")) and
            value(block, "startingDisplayed") in {None, "false"} and
            "Splash Screen" not in block and "SplashScreen" not in block)
    for key, field in (("focused", "mCurrentFocus"), ("focused_app", "mFocusedApp")):
        entries = re.findall(r"^\s*" + field + r"=(.*)$", text, flags=re.MULTILINE)
        flags[key] = (len(entries) == 1 and COMPONENT.search(entries[0]) is not None
                      and "Splash" not in entries[0])
    return {
        "ready": len(targets) == 1 and all(flag is True for flag in flags.values()),
        "target_activity_count": len(targets),
        "activity_identity_sha256": identity,
        "readback_sha256": hashlib.sha256(text.encode("utf-8")).hexdigest(),
        "flags": flags,
    }


def read_activity(adb, serial, timeout):
    try:
        result = subprocess.run(
            [adb, "-s", serial, "shell", "dumpsys", "activity", "activities"],
            capture_output=True, text=True, encoding="utf-8", timeout=timeout, check=False)
    except subprocess.TimeoutExpired:
        raise ReadinessFailure("ACTIVITY_READ_TIMEOUT") from None
    except (OSError, UnicodeError):
        raise ReadinessFailure("ACTIVITY_READ_UNAVAILABLE") from None
    if result.returncode:
        raise ReadinessFailure("ACTIVITY_READ_FAILED")
    return result.stdout


def wait_for_ready(read, *, clock=time.monotonic, sleep=time.sleep):
    started = clock()
    deadline = started + 30
    report = {"schema": SCHEMA, "package": PACKAGE, "activity": ".MainActivity",
              "ready": False, "required_consecutive_readbacks": 2,
              "consecutive_ready_readbacks": 0, "observations": []}
    previous_identity = None
    for _ in range(64):
        remaining = deadline - clock()
        if remaining <= 0:
            break
        try:
            observation = observe_dump(read(min(5, remaining)))
        except ReadinessFailure as error:
            report["failure_code"] = str(error)
            break
        observation["elapsed_ms"] = round((clock() - started) * 1000)
        report["observations"].append(observation)
        identity = observation["activity_identity_sha256"]
        if observation["ready"] and clock() < deadline:
            report["consecutive_ready_readbacks"] = (
                report["consecutive_ready_readbacks"] + 1
                if identity == previous_identity else 1)
            previous_identity = identity
            if report["consecutive_ready_readbacks"] >= 2:
                report["ready"] = True
                break
        else:
            report["consecutive_ready_readbacks"] = 0
            previous_identity = None
        remaining = deadline - clock()
        if remaining > 0:
            sleep(min(0.5, remaining))
    report["elapsed_ms"] = round((clock() - started) * 1000)
    if not report["ready"]:
        report.setdefault("failure_code", "PLP_DRAWN_READINESS_NOT_REACHED")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adb", required=True)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = wait_for_ready(lambda timeout: read_activity(args.adb, args.serial, timeout))
    try:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    except OSError:
        print("READINESS_REPORT_UNAVAILABLE", file=sys.stderr)
        return 1
    if not report["ready"]:
        print(report["failure_code"], file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
