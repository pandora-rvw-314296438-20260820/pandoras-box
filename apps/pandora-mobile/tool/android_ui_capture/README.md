# CI native accessibility capture

This inspector exists only for installed-APK acceptance. Flutter sends Android
text-field labels and validation messages through `AccessibilityNodeInfo.hintText`;
legacy `uiautomator dump` omits that property. Ordinary Flutter button labels use
`contentDescription`. Neither requires changing the production sign-in widgets.

The instrumentation targets its own package. It never launches or restarts PLP,
changes focus, types, clicks, signs in, or changes sessions. It requests no Android
permissions and contains no network or storage API. Only visible nodes belonging
to the exact allowlisted PLP package are serialized.

Build on the existing Android CI runner (JDK 17, platform 36, build-tools 36.0.0):

```sh
bash apps/pandora-mobile/tool/android_ui_capture/build.sh "$RUNNER_TEMP/ui-capture" "$RUNNER_DEBUG_KEYSTORE"
adb install -r "$RUNNER_TEMP/ui-capture/pandora-ui-capture.apk"
```

The keystore is supplied by the runner; never commit it. The script defaults only
to Android's public debug signing convention. A custom debug key can supply
`UI_CAPTURE_KEY_ALIAS`, `UI_CAPTURE_STORE_PASSWORD`, and `UI_CAPTURE_KEY_PASSWORD`
through runner environment variables. Do not enable shell tracing around signing.

With the PLP sign-in or empty-validation screen already foreground:

```sh
timeout 20s adb shell am instrument -w -r \
  -e target_package com.banataosystems.pandora.plp \
  com.banataosystems.pandora.uicapture/.CaptureInstrumentation
```

The final instrumentation Bundle reports `status=ok`,
`capture_schema=pandora.android.ui-capture.v1`, `node_count`, and `capture_base64`.
Decode that single base64 result as UTF-8 XML. Require success and exact schema;
never interpret a missing capture or an instrumentation process exit alone as
acceptance. Failure emits only a fixed `error_code`. The inspector polls for at
most five seconds for real input hint metadata plus noninput labels, rather than
returning Flutter's initial native frame. This readiness check does not match or
replace expected labels. If the target is visible without field semantics it
fails `SEMANTICS_NOT_READY`; a missing target fails `TARGET_NOT_VISIBLE`. The
caller's 20-second timeout also bounds Android automation connection/binder overhead.

The flat `hierarchy/node` XML includes exact package/class, `text`, `content-desc`,
`hint`, screen bounds, enabled/clickable/password/editable flags. Inputs always
have empty `text` and `content-desc`, even when a password is visible. Their
semantic hints remain; occurrences of any entered value are redacted from every
recorded label/hint. A maximum of 512 visited nodes, depth 32, bounded label length
and bounded XML size prevents unbounded collection. Out-of-package text is never
collected. No screenshots or general device dumps are produced by this helper.

Acceptance must still check the actual native field hints (`Email`, `Password`),
password flag, exact empty-submit validation messages, enabled/clickable Sign in
button and nonempty bounds. This capture is evidence, not an assertion shortcut.
It does not prove authentication, physical-device behavior, signing readiness or
production acceptance.

Host-only formatter regression test (no Android/device/dependencies):

```sh
mkdir -p "$RUNNER_TEMP/capture-tests"
javac --release 8 -d "$RUNNER_TEMP/capture-tests" \
  apps/pandora-mobile/tool/android_ui_capture/src/com/banataosystems/pandora/uicapture/CaptureXml.java \
  apps/pandora-mobile/tool/android_ui_capture/test/CaptureXmlTest.java
java -cp "$RUNNER_TEMP/capture-tests" CaptureXmlTest
```
