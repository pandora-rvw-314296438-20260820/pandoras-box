#!/usr/bin/env python3
"""Fail-closed verifier for Pandora Android physical-device acceptance candidates.

This tool never promotes a validation APK to production by itself. It binds an APK to
its exact-source manifest, verifies Android package/version/signing evidence, and can
run a bounded real-device install/launch/force-stop/relaunch smoke check through adb.
Network-switch and authenticated customer-journey proof remain explicit external gates.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Mapping, Sequence

EXPECTED_PACKAGE = "com.banataosystems.pandora_mobile"
FALSE_GATES = (
    "physical_device_verified",
    "wifi_journey_verified",
    "mobile_data_journey_verified",
    "authenticated_owner_journey_verified",
    "rollback_verified",
)


class VerificationError(RuntimeError):
    pass


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_manifest(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise VerificationError(f"invalid manifest line: {raw_line!r}")
        key, value = line.split("=", 1)
        key = key.strip()
        if not key or key in values:
            raise VerificationError(f"invalid or duplicate manifest key: {key!r}")
        values[key] = value.strip()
    return values


def require_manifest_binding(
    manifest: Mapping[str, str],
    *,
    source_sha: str,
    apk_sha256: str,
    package_name: str,
    app_version: str,
) -> None:
    if not re.fullmatch(r"[0-9a-f]{40}", source_sha):
        raise VerificationError("expected source SHA must be lowercase 40-hex")
    if manifest.get("source_sha") != source_sha:
        raise VerificationError("manifest source SHA does not match requested source")
    if manifest.get("apk_sha256") != apk_sha256:
        raise VerificationError("manifest APK SHA-256 does not match candidate bytes")
    if manifest.get("android_package") != package_name:
        raise VerificationError("manifest Android package does not match candidate")
    if manifest.get("app_version") != app_version:
        raise VerificationError("manifest app version does not match candidate")
    if manifest.get("artifact_class") != "validation-candidate":
        raise VerificationError("candidate is not an exact-source validation artifact")
    if manifest.get("production_release") != "false":
        raise VerificationError("validation manifest must not self-assert production release")
    for key in FALSE_GATES:
        if manifest.get(key) != "false":
            raise VerificationError(f"CI manifest must leave {key}=false until external proof")


def run_checked(command: Sequence[str]) -> str:
    try:
        completed = subprocess.run(
            list(command),
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        output = getattr(error, "stdout", None) or str(error)
        raise VerificationError(f"command failed: {' '.join(command)}\n{output}") from error
    return completed.stdout


def parse_badging(text: str) -> tuple[str, str, str]:
    package = re.search(r'package: name=\'([^\']+)\'', text)
    version_code = re.search(r'versionCode=\'([^\']+)\'', text)
    version_name = re.search(r'versionName=\'([^\']+)\'', text)
    if not package or not version_code or not version_name:
        raise VerificationError("aapt badging is missing package/version identity")
    return package.group(1), version_name.group(1), version_code.group(1)


def signer_is_debug(signing_text: str) -> bool:
    lowered = signing_text.lower()
    return "android debug" in lowered or "cn=android debug" in lowered


def adb_prefix(adb: str, serial: str | None) -> list[str]:
    prefix = [adb]
    if serial:
        prefix += ["-s", serial]
    return prefix


def smoke_device(adb: str, serial: str | None, apk: Path, package_name: str) -> dict[str, bool]:
    prefix = adb_prefix(adb, serial)
    if run_checked([&prefix, "get-state"]).strip() != "device":
        raise VerificationError("adb target is not in device state")
    run_checked([*prefix, "install", "-r", str(apk)])
    if not run_checked([*prefix, "shell", "pm", "path", package_name]).strip().startswith("package:"):
        raise VerificationError("installed package cannot be resolved on device")
    run_checked([*prefix, "shell", "monkey", "-p", package_name, "-c", "android.intent.category.LAUNCHER", "1"])
    first_pid = run_checked([*prefix, "shell", "pidof", package_name]).strip()
    if not first_pid:
        raise VerificationError("package did not remain launched after first start")
    run_checked([*prefix, "shell", "am", "force-stop", package_name])
    run_checked([*prefix, "shell", "monkey", "-p", package_name, "-c", "android.intent.category.LAUNCHER", "1"])
    second_pid = run_checked([*prefix, "shell", "pidof", package_name]).strip()
    if not second_pid:
        raise VerificationError("package did not relaunch after force-stop")
    return {
        "adb_device_online": True,
        "install_verified": True,
        "launch_verified": True,
        "force_stop_relaunch_verified": True,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apk", required=True, type=Path)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--expected-source-sha", required=True)
    parser.add_argument("--aapt", default="aapt")
    parser.add_argument("--apksigner", default="apksigner")
    parser.add_argument("--adb", default="adb")
    parser.add_argument("--serial")
    parser.add_argument("--smoke-device", action="store_true")
    parser.add_argument("--require-production-signer", action="store_true")
    args = parser.parse_args()

    if not args.apk.is_file() or not args.manifest.is_file():
        raise VerificationError("APk and exact-source manifest must both exist")

    manifest = parse_manifest(args.manifest)
    apk_sha = sha256_file(args.apk)
    app_version = manifest.get("app_version", "")
    require_manifest_binding(
        manifest,
        source_sha=args.expected_source_sha,
        apk_sha256=apk_sha,
        package_name=EXPECTED_PACKAGE,
        app_version=app_version,
    )

    badging = run_checked([args.aapt, "dump", "badging", str(args.apk)])
    package_name, version_name, version_code = parse_badging(badging)
    if package_name != EXPECTED_PACKAGE:
        raise VerificationError(f"unexpected Android package: {package_name}")
    expected_version_name = app_version.split("+", 1)[0]
    expected_version_code = app_version.split("+", 1)[1] if "+" in app_version else ""
    if version_name != expected_version_name or version_code != expected_version_code:
        raise VerificationError("APK version identity does not match exact-source manifest")

    signing = run_checked([args.apksigner, "verify", "--verbose", "--print-certs", str(args.apk)])
    debug_signer = signer_is_debug(signing)
    if args.require_production_signer and debug_signer:
        raise VerificationError("production acceptance cannot use the Android debug signer")

    evidence: dict[str, object] = {
        "source_sha": args.expected_source_sha,
        "apk_sha256": apk_sha,
        "android_package": package_name,
        "version_name": version_name,
        "version_code": version_code,
        "debug_signer": debug_signer,
        "manifest_bound": True,
        "physical_device_verified": False,
        "wifi_journey_verified": False,
        "mobile_data_journey_verified": False,
        "authenticated_owner_journey_verified": False,
        "network_switch_verified": False,
    }
    if args.smoke_device:
        evidence.update(smoke_device(args.adb, args.serial, args.apk, package_name))
        evidence["physical_device_verified"] = True

    print(json.dumps(evidence, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except VerificationError as error:
        print(f"PHYSICAL_ANDROID_ACCEPTANCE_FAIL: {error}", file=sys.stderr)
        raise SystemExit(2)
