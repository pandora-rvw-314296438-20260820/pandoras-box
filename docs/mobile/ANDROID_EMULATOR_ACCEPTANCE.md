# Android emulator acceptance

Pandora Mobile treats emulator acceptance as an external runtime proof, separate from GitHub-hosted build verification and separate from physical Redmi acceptance.

The GitHub mobile workflow still produces an exact-source validation candidate. Its manifest must keep both `emulator_device_verified=false` and `physical_device_verified=false`. Neither CI nor a release publisher is allowed to self-assert runtime acceptance that did not happen there.

## What emulator acceptance proves

The Windows verifier fails closed unless all of the following are observed on the selected ADB target:

- the candidate APK and manifest bind to the expected Git commit, source tree, package, version, permissions, signer, and APK SHA-256;
- the ADB serial is explicitly an `emulator-*` target;
- `ro.kernel.qemu=1`;
- Android reports `sys.boot_completed=1`;
- the API level is at least 35;
- the exact APK installs and the installed version matches;
- `com.banataosystems.pandora_mobile/.MainActivity` becomes the resumed activity;
- Pandora remains running after launch;
- a force-stop followed by a second launch succeeds; and
- Pandora does not appear in the Android crash buffer after the acceptance run.

Successful evidence sets `emulator_device_verified=true` while deliberately leaving `physical_device_verified=false`.

## Windows execution

Run from an exact committed worktree on the emulator host after obtaining the exact APK and manifest:

```powershell
apps\pandora-mobile\tool\run_windows_emulator_acceptance.ps1 `
  -Apk C:\path\to\app-debug.apk `
  -Manifest C:\path\to\pandora-mobile-artifact-manifest.txt `
  -ExpectedSourceSha <40-hex-main-or-PR-SHA> `
  -Serial emulator-5554
```

The wrapper also verifies that the worktree HEAD equals the requested source SHA and that tracked/index content is clean. It resolves ADB and Android build-tools from `C:\Android\Sdk` by default.

Evidence is written beneath `.pandora-mobile-emulator-evidence/<short-sha>/<timestamp>/` and is ignored by Git. The directory contains:

- `acceptance.json` — bounded machine-readable acceptance evidence;
- `events.jsonl` — real execution events suitable for Build Theatre ingestion.

The event stream records start, exact-source verification, emulator verification, installation, launch, relaunch, crash-buffer verification, completion, and genuine failure. It does not generate synthetic percentages or simulated success.
