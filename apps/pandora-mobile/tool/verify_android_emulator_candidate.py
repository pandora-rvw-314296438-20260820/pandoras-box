#!/usr/bin/env python3
"""Fail-closed exact-source acceptance for Pandora on an Android emulator."""
from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import verify_physical_android_candidate as base

EXPECTED_PACKAGE = base.EXPECTED_PACKAGE
MAIN_ACTIVITY = f"{EXPECTED_PACKAGE}/.MainActivity"
DEFAULT_MIN_API_LEVEL = 35


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def emit_event(path: Path | None, event: str, **details: Any) -> None:
    if path is None:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    record = {"at": utc_now(), "event": event, **details}
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, sort_keys=True) + "\n")


def verify_candidate_bytes(
    apk: Path,
    manifest_path: Path,
    source_sha: str,
    source_tree: str,
    aapt: str,
    apksigner: str,
) -> dict[str, Any]:
    if not apk.is_file() or not manifest_path.is_file():
        raise base.VerificationError("APK and exact-source manifest must both exist")
    manifest = base.parse_manifest(manifest_path)
    apk_sha = base.sha256_file(apk)
    app_version = manifest.get("app_version", "")
    base.require_manifest_binding(
        manifest,
        source_sha=source_sha,
        source_tree=source_tree,
        apk_sha256=apk_sha,
        package_name=EXPECTED_PACKAGE,
        app_version=app_version,
    )
    badging = base.run_checked([aapt, "dump", "badging", str(apk)])
    package_name, version_name, version_code = base.parse_badging(badging)
    expected_name = app_version.split("+", 1)[0]
    expected_code = app_version.split("+", 1)[1] if "+" in app_version else ""
    if package_name != EXPECTED_PACKAGE or version_name != expected_name or version_code != expected_code:
        raise base.VerificationError("APK identity does not match exact-source manifest")
    permissions = base.run_checked([aapt, "dump", "permissions", str(apk)])
    base.require_safe_permissions(permissions)
    signing = base.run_checked([apksigner, "verify", "--verbose", "--print-certs", str(apk)])
    return {
        "source_sha": source_sha,
        "source_tree": source_tree,
        "apk_sha256": apk_sha,
        "android_package": package_name,
        "version_name": version_name,
        "version_code": version_code,
        "debug_signer": base.signer_is_debug(signing),
        "signer_sha256": base.parse_signer_sha256(signing),
        "manifest_bound": True,
    }


def verify_emulator_identity(adb: str, serial: str, minimum_api_level: int) -> dict[str, Any]:
    if not serial.startswith("emulator-"):
        raise base.VerificationError("emulator acceptance requires an explicit emulator-* serial")
    prefix = base.adb_prefix(adb, serial)
    if base.run_checked([*prefix, "get-state"]).strip() != "device":
        raise base.VerificationError("adb emulator target is not in device state")
    if base.run_checked([*prefix, "shell", "getprop", "ro.kernel.qemu"]).strip() != "1":
        raise base.VerificationError("adb target is not reporting QEMU")
    if base.run_checked([*prefix, "shell", "getprop", "sys.boot_completed"]).strip() != "1":
        raise base.VerificationError("Android emulator boot is not complete")
    api_text = base.run_checked([*prefix, "shell", "getprop", "ro.build.version.sdk"]).strip()
    if not api_text.isdigit() or int(api_text) < minimum_api_level:
        raise base.VerificationError(f"Android emulator API level must be >= {minimum_api_level}")
    release = base.run_checked([*prefix, "shell", "getprop", "ro.build.version.release"]).strip()
    return {
        "emulator_serial": serial,
        "emulator_verified": True,
        "qemu_verified": True,
        "boot_completed": True,
        "android_api_level": int(api_text),
        "android_release": release,
    }


def install_exact_candidate(
    adb: str,
    serial: str,
    apk: Path,
    version_name: str,
    version_code: str,
) -> None:
    prefix = base.adb_prefix(adb, serial)
    base.run_checked([*prefix, "install", "-r", str(apk)])
    package_path = base.run_checked([*prefix, "shell", "pm", "path", EXPECTED_PACKAGE]).strip()
    if not package_path.startswith("package:"):
        raise base.VerificationError("installed Pandora package cannot be resolved")
    installed_name, installed_code = base.parse_installed_version(
        base.run_checked([*prefix, "shell", "dumpsys", "package", EXPECTED_PACKAGE])
    )
    if installed_name != version_name or installed_code != version_code:
        raise base.VerificationError("installed package version identity does not match exact APK candidate")


def require_resumed_activity(activity_dump: str) -> None:
    pattern = re.compile(r"(?:mResumedActivity|topResumedActivity).*com\.banataosystems\.pandora_mobile/\.MainActivity")
    if not pattern.search(activity_dump):
        raise base.VerificationError("Pandora MainActivity is not the resumed activity")


def launch_and_verify(adb: str, serial: str) -> str:
    prefix = base.adb_prefix(adb, serial)
    base.run_checked([*prefix, "shell", "am", "force-stop", EXPECTED_PACKAGE])
    base.run_checked([*prefix, "shell", "am", "start", "-W", "-n", MAIN_ACTIVITY])
    pid = base.run_checked([*prefix, "shell", "pidof", EXPECTED_PACKAGE]).strip()
    if not pid:
        raise base.VerificationError("Pandora process did not remain running after launch")
    activity_dump = base.run_checked([*prefix, "shell", "dumpsys", "activity", "activities"])
    require_resumed_activity(activity_dump)
    return pid


def verify_crash_buffer(adb: str, serial: str) -> None:
    prefix = base.adb_prefix(adb, serial)
    crash = base.run_checked([*prefix, "logcat", "-b", "crash", "-d", "-t", "100"])
    if EXPECTED_PACKAGE.lower() in crash.lower():
        raise base.VerificationError("Pandora appears in the Android crash buffer")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apk", required=True, type=Path)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--expected-source-sha", required=True)
    parser.add_argument("--expected-source-tree", required=True)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--aapt", default="aapt")
    parser.add_argument("--apksigner", default="apksigner")
    parser.add_argument("--adb", default="adb")
    parser.add_argument("--minimum-api-level", type=int, default=DEFAULT_MIN_API_LEVEL)
    parser.add_argument("--events-output", type=Path)
    parser.add_argument("--evidence-output", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    source = args.expected_source_sha
    emit_event(args.events_output, "acceptance_started", source_sha=source, serial=args.serial)
    candidate = verify_candidate_bytes(
        args.apk,
        args.manifest,
        source,
        args.expected_source_tree,
        args.aapt,
        args.apksigner,
    )
    emit_event(args.events_output, "exact_source_verified", source_sha=source, apk_sha256=candidate["apk_sha256"])
    emulator = verify_emulator_identity(args.adb, args.serial, args.minimum_api_level)
    emit_event(args.events_output, "emulator_verified", source_sha=source, serial=args.serial, api_level=emulator["android_api_level"])
    prefix = base.adb_prefix(args.adb, args.serial)
    base.run_checked([*prefix, "logcat", "-b", "crash", "-c"])
    install_exact_candidate(args.adb, args.serial, args.apk, candidate["version_name"], candidate["version_code"])
    emit_event(args.events_output, "apk_installed", source_sha=source, serial=args.serial, version_name=candidate["version_name"])
    first_pid = launch_and_verify(args.adb, args.serial)
    emit_event(args.events_output, "app_launch_verified", source_sha=source, serial=args.serial, pid=first_pid)
    second_pid = launch_and_verify(args.adb, args.serial)
    emit_event(args.events_output, "app_relaunch_verified", source_sha=source, serial=args.serial, pid=second_pid)
    verify_crash_buffer(args.adb, args.serial)
    emit_event(args.events_output, "crash_buffer_verified", source_sha=source, serial=args.serial)
    evidence = {
        **candidate,
        **emulator,
        "execution_target": "android-emulator",
        "install_verified": True,
        "launch_verified": True,
        "force_stop_relaunch_verified": True,
        "pandora_crash_buffer_empty": True,
        "emulator_device_verified": True,
        "physical_device_verified": False,
        "verified_at": utc_now(),
    }
    if args.evidence_output is not None:
        args.evidence_output.parent.mkdir(parents=True, exist_ok=True)
        args.evidence_output.write_text(json.dumps(evidence, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    emit_event(args.events_output, "acceptance_completed", source_sha=source, serial=args.serial, result="verified")
    print(json.dumps(evidence, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except base.VerificationError as error:
        try:
            parsed = parse_args()
            emit_event(parsed.events_output, "acceptance_failed", source_sha=parsed.expected_source_sha, serial=parsed.serial, error=str(error))
        except Exception:
            pass
        print(f"ANDROID_EMULATOR_ACCEPTANCE_FAIL: {error}", file=sys.stderr)
        raise SystemExit(2)
