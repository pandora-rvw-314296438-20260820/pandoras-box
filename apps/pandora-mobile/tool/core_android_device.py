#!/usr/bin/env python3
"""Install verified bytes and collect a bounded, content-free Android receipt."""
from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time

from core_artifact_provenance import ANDROID_PACKAGE, digest_file


@dataclass(frozen=True)
class AdbFailure:
    command_class: str
    failure_kind: str
    exit_code: int | None
    stderr_category: str


class DeviceFailure(RuntimeError):
    def __init__(self, code: str, *, adb_failure: AdbFailure | None = None):
        super().__init__(code)
        self.adb_failure = adb_failure


def adb_failure_receipt(error: Exception) -> dict | None:
    failure = getattr(error, "adb_failure", None)
    return asdict(failure) if isinstance(failure, AdbFailure) else None


def classify_adb_failure(arguments: tuple[str, ...], kind: str,
                         exit_code: int | None, stderr: str = "") -> AdbFailure:
    command_class = {
        ("shell", "dumpsys", "input_method"): "read_ime_state",
        ("shell", "dumpsys", "window", "displays"): "read_window_state",
        ("shell", "ps", "-A", "-o", "NAME"): "read_process_state",
        ("shell", "dumpsys", "activity", "activities"): "read_activity_state",
    }.get(arguments, "other")
    # These are observed ADB error signatures, not a causal diagnosis. Do not
    # classify generic child output such as "closed", "error" or "timeout".
    signatures = {
        "device_offline": r"(?:adb: )?error: device offline",
        "device_unauthorized": r"(?:adb: )?error: device unauthorized\.",
        "no_devices": r"(?:adb: )?error: no devices/emulators found",
        "device_not_found": r"(?:adb: )?error: device '[^'\r\n]+' not found",
    }
    categories = {category for category, signature in signatures.items()
                  if any(re.fullmatch(signature, line) for line in stderr.splitlines())}
    category = next(iter(categories)) if len(categories) == 1 else "ambiguous" if categories else "unknown"
    return AdbFailure(command_class, kind, exit_code, category)


def require(condition: bool, code: str) -> None:
    if not condition:
        raise DeviceFailure(code)


class AndroidDevice:
    def __init__(self, serial: str, adb: str = "adb"):
        require(bool(re.fullmatch(r"[a-zA-Z0-9._:-]+", serial)), "INVALID_DEVICE_SERIAL")
        self.serial = serial
        self.adb = adb

    def run(self, *arguments: str, timeout: int = 30, check: bool = True) -> str:
        try:
            result = subprocess.run([self.adb, "-s", self.serial, *arguments],
                                    capture_output=True, text=True, timeout=timeout)
        except subprocess.TimeoutExpired as error:
            # Keep the existing exception type/control flow, without copying
            # its command, partial output or exception text into evidence.
            error.adb_failure = classify_adb_failure(arguments, "timeout", None)
            raise
        if check and result.returncode:
            # Do not copy device output or command arguments into public logs.
            raise DeviceFailure("ADB_COMMAND_FAILED", adb_failure=classify_adb_failure(
                arguments, "nonzero_exit", result.returncode, result.stderr))
        return result.stdout

    def shell(self, *arguments: str, **kwargs) -> str:
        return self.run("shell", *arguments, **kwargs)

    def property(self, name: str) -> str:
        require(bool(re.fullmatch(r"[a-zA-Z0-9_.]+", name)), "INVALID_PROPERTY")
        return self.shell("getprop", name).strip()

    def installed_digest(self) -> str | None:
        paths = self.shell("pm", "path", ANDROID_PACKAGE, check=False).splitlines()
        paths = [line.removeprefix("package:") for line in paths
                 if line.startswith("package:") and line.endswith("/base.apk")]
        if not paths:
            return None
        require(len(paths) == 1 and bool(re.fullmatch(r"/data/app/[a-zA-Z0-9_+=.~/-]+/base.apk", paths[0])),
                "UNEXPECTED_INSTALLED_APK_PATH")
        output = self.shell("sha256sum", paths[0])
        match = re.match(r"([a-f0-9]{64})\s", output)
        require(match is not None, "INSTALLED_DIGEST_UNAVAILABLE")
        return match.group(1)

    def install_exact(self, receipt: dict) -> dict:
        require(receipt.get("schema") == "pandora-core-android-artifact-v1",
                "VERIFIED_ARTIFACT_RECEIPT_REQUIRED")
        require(receipt.get("android_package") == ANDROID_PACKAGE,
                "NON_CORE_PACKAGE_REJECTED")
        apk = Path(receipt["apk_path"])
        require(digest_file(apk) == receipt["apk_sha256"], "APK_CHANGED_BEFORE_INSTALL")
        sdk = os.environ.get("ANDROID_SDK_ROOT") or os.environ.get("ANDROID_HOME")
        require(bool(sdk), "ANDROID_SDK_ROOT_REQUIRED_FOR_PACKAGE_VERIFICATION")
        package_metadata = inspect_apk(receipt, Path(sdk))
        require(self.property("sys.boot_completed") == "1", "ANDROID_NOT_BOOTED")
        abis = self.property("ro.product.cpu.abilist").split(",")
        require("arm64-v8a" in abis, "ARM64_APK_NOT_SUPPORTED_BY_DEVICE")
        before = self.installed_digest()
        if before != receipt["apk_sha256"]:
            installed = self.run("install", "-r", str(apk), timeout=180)
            require("Success" in installed, "APK_INSTALL_NOT_CONFIRMED")
        after = self.installed_digest()
        require(after == receipt["apk_sha256"], "INSTALLED_APK_DIGEST_MISMATCH")
        info = self.shell("dumpsys", "package", ANDROID_PACKAGE)
        name = re.search(r"\bversionName=([^\s]+)", info)
        code = re.search(r"\bversionCode=(\d+)", info)
        expected_name, separator, expected_code = receipt["app_version"].partition("+")
        require(separator and name is not None and code is not None
                and name.group(1) == expected_name and code.group(1) == expected_code,
                "INSTALLED_VERSION_MISMATCH")
        native_bridge = self.property("ro.dalvik.vm.native.bridge")
        emulator = self.property("ro.kernel.qemu") == "1"
        self.shell("settings", "put", "secure", "show_ime_with_hard_keyboard", "1")
        self.shell("dumpsys", "gfxinfo", ANDROID_PACKAGE, "reset", check=False)
        return {
            **receipt, "installed": True, "installed_apk_sha256": after,
            "apk_package_evidence": package_metadata,
            "previous_installed_apk_sha256": before, "installed_package": ANDROID_PACKAGE,
            "installed_version": name.group(1) + "+" + code.group(1),
            "device": {
                "serial_sha256": hashlib.sha256(self.serial.encode()).hexdigest(),
                "android_api": self.property("ro.build.version.sdk"),
                "android_release": self.property("ro.build.version.release"),
                "fingerprint": self.property("ro.build.fingerprint"),
                "supported_abis": abis, "native_bridge": native_bridge,
                "emulator": emulator,
                "abi_translation": emulator and "x86_64" in abis,
                "screen_size": self.shell("wm", "size").strip(),
                "screen_density": self.shell("wm", "density").strip(),
            },
            "runtime_verified": False, "production_verified": False,
        }

    def ime_visible(self) -> bool:
        # Android 15 IMMS sets mInputShown at show dispatch, before the IME
        # window has necessarily laid out. This flag alone is not geometry.
        state = self.ime_state()
        require(state is not None, "ANDROID_IME_VISIBILITY_NOT_OBSERVABLE")
        return state

    def ime_state(self, *, timeout: int = 30) -> bool | None:
        return parse_ime_state(self.shell("dumpsys", "input_method", timeout=timeout))

    def window_insets(self, *, timeout: int = 30) -> dict:
        # Read the live display controller, not historical window/request logs.
        # Only numeric geometry leaves this method; the dump is never persisted.
        return parse_window_insets(self.shell("dumpsys", "window", "displays", timeout=timeout))

    def metrics(self) -> dict:
        graphics = self.shell("dumpsys", "gfxinfo", ANDROID_PACKAGE, check=False)
        memory = self.shell("dumpsys", "meminfo", ANDROID_PACKAGE, check=False)
        result = parse_metrics(graphics, memory)
        result["measurement_context"] = "Android candidate; emulator translation may affect timings"
        return result


def parse_package_evidence(badging: str, signing: str, expected_version: str) -> dict:
    package = re.search(r"^package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'",
                        badging, re.MULTILINE)
    require(package is not None, "APK_PACKAGE_METADATA_UNAVAILABLE")
    require(package.group(1) == ANDROID_PACKAGE, "APK_PACKAGE_METADATA_MISMATCH")
    require(package.group(3) + "+" + package.group(2) == expected_version,
            "APK_VERSION_METADATA_MISMATCH")
    abi = re.search(r"^native-code:\s*(.+)$", badging, re.MULTILINE)
    require(abi is not None, "APK_NATIVE_ABI_UNAVAILABLE")
    architectures = re.findall(r"'([^']+)'", abi.group(1))
    require(architectures == ["arm64-v8a"], "CANONICAL_ARM64_APK_ABI_CHANGED")
    signers = re.findall(r"Signer #\d+ certificate SHA-256 digest:\s*([a-fA-F0-9]{64})", signing)
    require(len(signers) == 1, "APK_SIGNER_IDENTITY_AMBIGUOUS")
    modern = bool(re.search(r"Verified using v[23](?:\.1)? scheme[^\n]*:\s*true", signing))
    require(modern, "APK_MODERN_SIGNATURE_VERIFICATION_REQUIRED")
    return {"package": package.group(1), "version_name": package.group(3),
            "version_code": package.group(2), "native_abis": architectures,
            "signer_sha256": signers[0].lower(), "modern_signature_verified": True,
            "debug_signer": "CN=Android Debug" in signing,
            "production_signing_verified": False}


def inspect_apk(receipt: dict, sdk: Path) -> dict:
    apk = Path(receipt["apk_path"])
    require(digest_file(apk) == receipt["apk_sha256"], "APK_CHANGED_BEFORE_INSPECTION")
    build_tools = sdk / "build-tools/36.0.0"
    aapt = build_tools / "aapt"
    require(aapt.is_file() and (build_tools / "apksigner").is_file(),
            "PINNED_ANDROID_PACKAGE_TOOLS_REQUIRED")
    aapt.chmod(aapt.stat().st_mode | 0o111)
    badging = subprocess.run([str(aapt), "dump", "badging", str(apk)],
                             capture_output=True, text=True, timeout=45)
    signing = subprocess.run(["bash", str(build_tools / "apksigner"), "verify", "--verbose",
                              "--print-certs", str(apk)], capture_output=True, text=True, timeout=60)
    require(badging.returncode == 0 and signing.returncode == 0, "APK_PACKAGE_VERIFICATION_FAILED")
    return parse_package_evidence(badging.stdout, signing.stdout, receipt["app_version"])


def parse_ime_visibility(value: str) -> bool:
    return parse_ime_state(value) is True


def parse_ime_state(value: str) -> bool | None:
    for pattern in (r"\bmInputShown=(true|false)\b", r"\bisInputViewShown=(true|false)\b",
                    r"\bimeVisible=(true|false)\b"):
        matches = re.findall(pattern, value)
        if matches:
            return matches[0] == "true" if len(matches) == 1 else None
    return None


def ime_geometry_observation(shown: bool | None, insets: dict) -> dict:
    """Retain numeric current-controller evidence, never titles or IME text."""
    dl, dt, dr, db = insets["display"]
    sources = [{"frame": tuple(source["frame"]), "visible": source["visible"]}
               for source in insets["sources"] if source["type"] == "ime"]
    usable = any(source["visible"] and
                 dl <= source["frame"][0] < source["frame"][2] <= dr and
                 dt <= source["frame"][1] < source["frame"][3] <= db
                 for source in sources)
    return {"input_shown": shown, "display": tuple(insets["display"]),
            "ime_sources": sources, "ready": shown is True and usable}


def parse_launch_result(value: str) -> dict:
    """Allowlist Android 15 am start -W fields; ambiguous fields stay unknown."""
    def one(field):
        matches = re.findall(r"^" + field + r":[ \t]*([^\n]*)$", value, re.MULTILINE)
        return matches[0].strip() if len(matches) == 1 else None
    status, state, activity = one("Status"), one("LaunchState"), one("Activity")
    result = {"status": status if status in {"ok", "timeout"} else None,
              "launch_state": state if state in {"COLD", "WARM", "HOT", "UNKNOWN"} else None,
              "canonical_activity": None if activity is None or not re.fullmatch(r"[a-zA-Z0-9_.]+/[a-zA-Z0-9_.$]+", activity) else activity in {
                  ANDROID_PACKAGE + "/.MainActivity", ANDROID_PACKAGE + "/" + ANDROID_PACKAGE + ".MainActivity"}}
    for field, key in (("TotalTime", "total_time_ms"), ("WaitTime", "wait_time_ms")):
        number = one(field)
        result[key] = int(number) if number is not None and re.fullmatch(r"\d{1,9}", number) else None
    return result


def parse_process_observation(value: str) -> dict:
    lines = value.strip().splitlines()
    if not lines or lines[0].strip() != "NAME":
        return {"observed": False, "canonical_process_count": None}
    return {"observed": True,
            "canonical_process_count": sum(line.strip() == ANDROID_PACKAGE for line in lines[1:])}


def parse_window_observation(value: str) -> dict:
    """Classify only the default display's current focus, never its title."""
    displays = list(re.finditer(r"^\s*Display: mDisplayId=(\d+)[^\n]*$", value, re.MULTILINE))
    indexes = [i for i, match in enumerate(displays) if match.group(1) == "0"]
    result = {"focus": "unobserved", "canonical_error_dialog": None,
              "canonical_anr_dialog": None, "window_exit_suffix_observed": None,
              "dialog_kind": "unobserved", "dialog_owner": "unobserved",
              "anr_process_sha256": None}
    if len(indexes) != 1:
        return result
    index = indexes[0]
    section = value[displays[index].end():displays[index + 1].start() if index + 1 < len(displays) else len(value)]
    matches = re.findall(r"^\s*mCurrentFocus=([^\n]*)$", section, re.MULTILINE)
    if len(matches) != 1:
        return result
    focus = matches[0].strip()
    if focus == "null":
        return {"focus": "none", "canonical_error_dialog": False, "canonical_anr_dialog": False,
                "window_exit_suffix_observed": False, "dialog_kind": "none", "dialog_owner": "none",
                "anr_process_sha256": None}
    window = re.fullmatch(r"Window\{[a-fA-F0-9]+ u\d+ (.+)\}", focus)
    if window is None:
        return result
    # Android 15 WindowState.toString appends this framework suffix outside
    # the title when mAnimatingExit is true. Never retain the title itself.
    serialized_title = window.group(1)
    exiting = serialized_title.endswith(" EXITING")
    title = serialized_title.removesuffix(" EXITING")
    canonical = title in {ANDROID_PACKAGE + "/.MainActivity",
                          ANDROID_PACKAGE + "/" + ANDROID_PACKAGE + ".MainActivity"}
    # Legacy canonical_* booleans describe the exact main process only.
    # dialog_owner separately preserves recognized Core auxiliary ownership.
    result = {"focus": "canonical_activity" if canonical else "other_window",
              "canonical_error_dialog": False, "canonical_anr_dialog": False,
              "window_exit_suffix_observed": exiting, "dialog_kind": "none", "dialog_owner": "none",
              "anr_process_sha256": None}
    for prefix, kind, field in (("Application Error:", "application_error", "canonical_error_dialog"),
                                ("Application Not Responding:", "application_anr", "canonical_anr_dialog")):
        if not title.startswith(prefix):
            continue
        result["dialog_kind"] = kind
        # AOSP uses one space followed by mProc.info.processName. Classify
        # exact identifiers only; malformed owner text must remain unknown.
        owner = title.removeprefix(prefix + " ")
        if not re.fullmatch(r"[a-zA-Z_][a-zA-Z0-9_.]*(?::[a-zA-Z0-9_.]+)?", owner):
            result["dialog_owner"] = "unobserved"
            result[field] = None
        elif owner == ANDROID_PACKAGE:
            result["dialog_owner"] = "canonical_main_process"
            result[field] = True
        elif owner.startswith(ANDROID_PACKAGE + ":"):
            result["dialog_owner"] = "canonical_auxiliary_process"
        elif owner == "com.android.systemui":
            # Pinned Android 15 SystemUI manifest's exact application process.
            result["dialog_owner"] = "system_ui_process"
        else:
            result["dialog_owner"] = "other_process"
        if kind == "application_anr" and result["dialog_owner"] != "unobserved":
            # Match only a validated exact UTF-8 process token against hashes
            # from the pristine SDK package/process inventory. Never hash an
            # arbitrary title, and never retain the token itself in receipts.
            result["anr_process_sha256"] = hashlib.sha256(owner.encode("utf-8")).hexdigest()
        break
    return result


def parse_keyguard_observation(value: str) -> dict:
    result = {}
    for field in ("mKeyguardShowing", "mAodShowing", "mKeyguardGoingAway"):
        values = re.findall(r"^\s*" + field + r"=(true|false)\s*$", value, re.MULTILINE)
        result[field] = values[0] == "true" if len(values) == 1 else None
    return result


def parse_historical_exit_observation(value: str) -> dict:
    # Exit records can predate this attempt, including our deliberate force-stop.
    # Do not attribute their reasons to the failed launch without a time fence.
    reasons = {4: "java_crash", 5: "native_crash", 6: "anr", 7: "initialization",
               10: "user_requested", 11: "user_stopped"}
    counts = {name: 0 for name in (*reasons.values(), "other")}
    # Only the structured line immediately after a record header/timestamp is
    # eligible. Never scan description prose for a process/reason substring.
    records = re.findall(r"^[ \t]*ApplicationExitInfo [^\n]*:\n"
                         r"[ \t]+timestamp=[^\n]*\bpid=\d+[^\n]*\n"
                         r"[ \t]+process=([^ \t\n]+) reason=(\d+) \([^\n]*?\) subreason=",
                         value, re.MULTILINE)
    matches = [reason for process, reason in records if process == ANDROID_PACKAGE]
    for reason in matches:
        counts[reasons.get(int(reason), "other")] += 1
    return {"scope": "historical_only_including_driver_force_stop",
            "current_launch_cause_established": False,
            "observed": bool(records),
            "recognized_record_count": len(matches) if records else None,
            "reason_counts": counts if records else None}


def parse_window_insets(value: str, display_id: int = 0) -> dict:
    """Parse Android 15 DisplayContent/InsetsStateController.dump geometry.

    Format is pinned to AOSP android-15.0.0_r1 InsetsState/InsetsSource dump;
    control-map copies and other displays cannot substitute current state.
    """
    displays = list(re.finditer(r"^\s*Display: mDisplayId=(\d+)[^\n]*$", value, re.MULTILINE))
    selected = [i for i, match in enumerate(displays) if int(match.group(1)) == display_id]
    require(len(selected) == 1, "ANDROID_DISPLAY_INSETS_NOT_OBSERVABLE")
    index = selected[0]
    section = value[displays[index].end():displays[index + 1].start() if index + 1 < len(displays) else len(value)]
    controllers = re.findall(r"^\s*WindowInsetsStateController\s*\n(.*?)^\s*Control map:",
                             section, re.MULTILINE | re.DOTALL)
    require(len(controllers) == 1, "ANDROID_INSETS_CONTROLLER_AMBIGUOUS")
    current = controllers[0]
    rectangle = r"Rect\(\s*(-?\d+),\s*(-?\d+)\s*-\s*(-?\d+),\s*(-?\d+)\s*\)"
    frame = re.search(r"\bmDisplayFrame=" + rectangle, current)
    cutout = re.search(r"\bmDisplayCutout=DisplayCutout\{insets=" + rectangle, current)
    require(frame is not None and cutout is not None, "ANDROID_SAFE_AREA_GEOMETRY_UNAVAILABLE")
    display = tuple(int(part) for part in frame.groups())
    cutout_insets = tuple(int(part) for part in cutout.groups())
    require(display[0] < display[2] and display[1] < display[3]
            and all(part >= 0 for part in cutout_insets), "INVALID_ANDROID_SAFE_AREA_GEOMETRY")
    sources = []
    for match in re.finditer(r"^\s*InsetsSource id=[a-fA-F0-9]+ type=(\w+) "
                             r"frame=\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]"
                             r"[^\n]*?\bvisible=(true|false)\b", current, re.MULTILINE):
        kind, *parts, visible = match.groups()
        sources.append({"type": kind, "frame": tuple(int(part) for part in parts),
                        "visible": visible == "true"})
    require({"statusBars", "navigationBars"}.issubset({source["type"] for source in sources}),
            "ANDROID_SYSTEM_BAR_GEOMETRY_UNAVAILABLE")
    return {"display": display, "cutout_insets": cutout_insets, "sources": sources}


def require_unoccluded(rect: tuple[int, int, int, int], insets: dict, code: str) -> None:
    left, top, right, bottom = rect
    dl, dt, dr, db = insets["display"]
    cl, ct, cr, cb = insets["cutout_insets"]
    require(dl + cl <= left < right <= dr - cr and dt + ct <= top < bottom <= db - cb, code)
    for source in insets["sources"]:
        if source["visible"] and source["type"] in {"statusBars", "navigationBars", "ime", "displayCutout"}:
            sl, st, sr, sb = source["frame"]
            if sl < sr and st < sb:
                require(not (left < sr and right > sl and top < sb and bottom > st), code)


def parse_metrics(graphics: str, memory: str) -> dict:
    result = {}
    for key, pattern in {
        "frames_rendered": r"Total frames rendered:\s*(\d+)",
        "janky_frames": r"Janky frames:\s*(\d+)",
        "frame_p50_ms": r"50th percentile:\s*(\d+)ms",
        "frame_p90_ms": r"90th percentile:\s*(\d+)ms",
        "frame_p95_ms": r"95th percentile:\s*(\d+)ms",
        "frame_p99_ms": r"99th percentile:\s*(\d+)ms",
    }.items():
        match = re.search(pattern, graphics)
        if match:
            result[key] = int(match.group(1))
    pss = re.search(r"TOTAL PSS:\s*(\d+)", memory)
    if pss:
        result["total_pss_kib"] = int(pss.group(1))
    result["frame_metrics_available"] = "frames_rendered" in result
    result["memory_metrics_available"] = "total_pss_kib" in result
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", default="emulator-5554")
    parser.add_argument("--adb", default="adb")
    parser.add_argument("--artifact-receipt", type=Path, required=True)
    parser.add_argument("--installed-receipt", type=Path, required=True)
    args = parser.parse_args()
    try:
        result = AndroidDevice(args.serial, args.adb).install_exact(
            json.loads(args.artifact_receipt.read_text()))
        args.installed_receipt.parent.mkdir(parents=True, exist_ok=True)
        args.installed_receipt.write_text(json.dumps(result, indent=2) + "\n")
        print(json.dumps({"installed": True, "source_sha": result["source_sha"],
                          "apk_sha256": result["apk_sha256"], "runtime_verified": False}))
        return 0
    except (DeviceFailure, OSError, ValueError, subprocess.SubprocessError) as error:
        print(json.dumps({"installed": False, "runtime_verified": False,
                          "failure_code": str(error) if isinstance(error, DeviceFailure)
                          else type(error).__name__}))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
