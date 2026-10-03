#!/usr/bin/env python3
"""Pinned Android runtime. Runs commands against an existing APK, never builds it."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import urllib.request
import zipfile

PACKAGES = (
    ("cmdline-tools;19.0", "19.0.0", "commandlinetools-linux-13114758_latest.zip",
     "7ec965280a073311c339e571cd5de778b9975026cfcbe79f2b1cdcb1e15317ee"),
    ("platform-tools", "37.0.1", "platform-tools_r37.0.1-linux.zip",
     "d230f13842f60f782a8645f9c813f8f845bf36089ea7289f28c48f17979313f1"),
    ("emulator", "37.2.12", "emulator-linux_x64-16428233.zip",
     "b08fc43d8608d2955f607f1b287beb525041e730086bdca3af152accac3af9c1"),
    ("build-tools;36.0.0", "36.0.0", "build-tools_r36_linux.zip",
     "5d9ac77fb6ff43d9da518a337b4fcf8f9097113df531d99ccefe80ef7ce8250b"),
    ("system-images;android-35;google_apis;x86_64", "9.0.0",
     "sys-img/google_apis/x86_64-35_r09.zip",
     "c67b9ba0ff5bc0eb6d046871bfa228af14d4d47b02f0cdae94f048e511b7566e"),
)


def environment(sdk: Path, avd_home: Path) -> dict:
    return {**os.environ, "ANDROID_HOME": str(sdk), "ANDROID_SDK_ROOT": str(sdk),
            "ANDROID_AVD_HOME": str(avd_home),
            "ADBUTILS_ADB_PATH": str(sdk / "platform-tools/adb"),
            "PATH": str(sdk / "platform-tools") + os.pathsep + os.environ["PATH"]}


def bootstrap(sdk: Path, avd_home: Path, evidence: Path) -> None:
    sdk.mkdir(parents=True, exist_ok=True)
    avd_home.mkdir(parents=True, exist_ok=True)
    evidence.mkdir(parents=True, exist_ok=True)
    records = []
    for package, revision, relative_url, expected in PACKAGES:
        with tempfile.TemporaryDirectory(prefix="pandora-core-sdk-") as temporary:
            archive = Path(temporary) / "package.zip"
            urllib.request.urlretrieve("https://dl.google.com/android/repository/" + relative_url, archive)
            digest = hashlib.sha256()
            with archive.open("rb") as file:
                for chunk in iter(lambda: file.read(1024 * 1024), b""):
                    digest.update(chunk)
            if digest.hexdigest() != expected:
                raise RuntimeError("ANDROID_SDK_CHECKSUM_MISMATCH")
            if package.startswith("cmdline-tools"):
                target = sdk / "cmdline-tools"
            elif package.startswith("system-images"):
                target = sdk / "system-images/android-35/google_apis"
            elif package.startswith("build-tools"):
                target = sdk / "build-tools"
            else:
                target = sdk
            target.mkdir(parents=True, exist_ok=True)
            with zipfile.ZipFile(archive) as zipped:
                for item in zipped.infolist():
                    if target.resolve() not in (target / item.filename).resolve().parents:
                        raise RuntimeError("UNSAFE_ANDROID_SDK_ARCHIVE")
                zipped.extractall(target)
                for item in zipped.infolist():
                    mode = item.external_attr >> 16
                    if not item.is_dir() and mode & 0o111:
                        path = target / item.filename
                        path.chmod(path.stat().st_mode | (mode & 0o777))
            if package.startswith("cmdline-tools"):
                (target / "cmdline-tools").rename(target / "19.0")
            elif package.startswith("build-tools"):
                (target / "android-16").rename(target / "36.0.0")
        records.append({"package": package, "revision": revision,
                        "archive": relative_url, "sha256": expected})
        print(json.dumps({"installed_sdk_package": package, "revision": revision}), flush=True)
    # Some official ZIP members do not retain their executable mode after
    # extraction (notably netsimd). Limit restoration to known SDK programs.
    binaries = [sdk / "platform-tools/adb", sdk / "emulator/emulator",
                sdk / "emulator/netsimd", sdk / "emulator/crashpad_handler",
                sdk / "build-tools/36.0.0/aapt", sdk / "build-tools/36.0.0/apksigner",
                sdk / "emulator/qemu/linux-x86_64/qemu-system-x86_64-headless"]
    binaries.extend((sdk / "cmdline-tools/19.0/bin").iterdir())
    for binary in binaries:
        if binary.is_file():
            binary.chmod(binary.stat().st_mode | 0o111)
    # Register the verified official emulator archive for offline avdmanager.
    (sdk / "emulator/package.xml").write_text('''<?xml version="1.0" encoding="UTF-8"?>
<ns2:repository xmlns:ns2="http://schemas.android.com/repository/android/common/02"
 xmlns:ns3="http://schemas.android.com/repository/android/generic/02"
 xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
 <localPackage path="emulator" obsolete="false">
  <type-details xsi:type="ns3:genericDetailsType"/>
  <revision><major>37</major><minor>2</minor><micro>12</micro></revision>
  <display-name>Android Emulator</display-name>
 </localPackage>
</ns2:repository>
''')
    result = subprocess.run([
        str(sdk / "cmdline-tools/19.0/bin/avdmanager"), "create", "avd",
        "--name", "pandora-core-api35", "--package",
        "system-images;android-35;google_apis;x86_64", "--device", "pixel_5",
        "--path", str(avd_home / "pandora-core-api35.avd"),
    ], input="no\n", text=True, capture_output=True, env=environment(sdk, avd_home))
    if result.returncode:
        raise RuntimeError("ANDROID_AVD_CREATION_FAILED")
    config = avd_home / "pandora-core-api35.avd/config.ini"
    values = dict(line.partition("=")[::2] for line in config.read_text().splitlines() if "=" in line)
    values.update({"hw.keyboard": "no", "hw.ramSize": "2560", "hw.cpu.ncore": "2",
                   "hw.gpu.enabled": "yes", "hw.gpu.mode": "software",
                   "disk.dataPartition.size": "3G"})
    config.write_text("".join(f"{key}={value}\n" for key, value in values.items()))
    (evidence / "android-sdk-receipt.json").write_text(json.dumps(records, indent=2) + "\n")


def run(sdk: Path, avd_home: Path, evidence: Path, command_file: Path,
        acceleration: str, boot_timeout: int, viewport: str) -> int:
    evidence.mkdir(parents=True, exist_ok=True)
    env = environment(sdk, avd_home)
    adb = str(sdk / "platform-tools/adb")
    if acceleration == "on" and not os.access("/dev/kvm", os.R_OK | os.W_OK):
        raise RuntimeError("KVM_ACCELERATION_UNAVAILABLE")
    subprocess.run([adb, "start-server"], capture_output=True, check=True, env=env)
    emulator_args = [str(sdk / "emulator/emulator"), "-avd", "pandora-core-api35",
                     "-no-window", "-accel", acceleration, "-gpu", "software",
                     "-noaudio", "-no-boot-anim", "-no-snapshot", "-no-metrics",
                     "-cores", "2", "-memory", "2560", "-camera-back", "none",
                     "-camera-front", "none", "-grpc-use-token"]
    start = time.monotonic()
    result = {"boot_completed": False, "acceleration": acceleration,
              "viewport": viewport, "runtime_verified": False, "production_verified": False}
    with (evidence.parent / "emulator-private.log").open("w") as log:
        process = subprocess.Popen(emulator_args, stdout=log, stderr=subprocess.STDOUT, env=env)
        try:
            while process.poll() is None and time.monotonic() - start < boot_timeout:
                try:
                    boot = subprocess.run([adb, "-s", "emulator-5554", "shell", "getprop",
                                           "sys.boot_completed"], capture_output=True, text=True,
                                          timeout=15, env=env)
                except subprocess.TimeoutExpired:
                    continue
                if boot.returncode == 0 and boot.stdout.strip() == "1":
                    result.update(boot_completed=True, boot_seconds=round(time.monotonic() - start, 2))
                    break
                time.sleep(2)
            if not result["boot_completed"]:
                raise RuntimeError("ANDROID_BOOT_NOT_CONFIRMED")
            size, density = ("720x1280", "320") if viewport == "small" else ("1080x2400", "440")
            for command in (["wm", "size", size], ["wm", "density", density],
                            ["input", "keyevent", "82"],
                            ["settings", "put", "secure", "show_ime_with_hard_keyboard", "1"]):
                subprocess.run([adb, "-s", "emulator-5554", "shell", *command],
                               check=True, capture_output=True, env=env)
            commands = json.loads(command_file.read_text())["commands"]
            if not commands or not all(isinstance(c, list) and all(isinstance(x, str) for x in c)
                                       for c in commands):
                raise RuntimeError("INVALID_RUNTIME_COMMANDS")
            for command in commands:
                status = subprocess.run(command, env=env).returncode
                if status:
                    result["command_exit_code"] = status
                    return status
            result["commands_completed"] = len(commands)
            return 0
        finally:
            (evidence / "android-boot-receipt.json").write_text(json.dumps(result, indent=2) + "\n")
            process.terminate()
            try:
                process.wait(timeout=20)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
            subprocess.run([adb, "kill-server"], capture_output=True, env=env)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["bootstrap", "run"])
    parser.add_argument("--sdk-root", type=Path, required=True)
    parser.add_argument("--avd-home", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--command-json", type=Path)
    parser.add_argument("--acceleration", choices=["on", "off"], default="on")
    parser.add_argument("--boot-timeout", type=int, default=480)
    parser.add_argument("--viewport", choices=["small", "tall"], default="small")
    args = parser.parse_args()
    try:
        if args.action == "bootstrap":
            bootstrap(args.sdk_root.resolve(), args.avd_home.resolve(), args.evidence.resolve())
            return 0
        if args.command_json is None:
            parser.error("run requires --command-json")
        return run(args.sdk_root.resolve(), args.avd_home.resolve(), args.evidence.resolve(),
                   args.command_json, args.acceleration, args.boot_timeout, args.viewport)
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(json.dumps({"android_runtime_completed": False,
                          "failure_code": str(error) if isinstance(error, RuntimeError)
                          else type(error).__name__}))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
