# Automatic phone model lifecycle — issue #664

Owner acceptance is the release gate. A compilation, JVM test, simulated route, Storage receipt, or uploaded APK is not a physical phone PASS.

Source ownership: repository-authored Dart, native Android overlays, build configuration, CI, model contract and Edge Functions. No FlutterFlow-generated project is edited.

## Implemented candidate path
- First frame precedes model provisioning. Supabase grants are fetched in the background after normal authentication.
- A non-exported Android service runs llama.cpp in its own process. Flutter only holds readiness and bounded IPC.
- Model bytes live in app-private no-backup storage, keyed by SHA256. Range resume uses a temporary file. Size and SHA256 precede atomic file promotion.
- Only real native token generation permits LOCAL_READY and active-pointer promotion. A pending activation marker survives native process death and protects the previous active version.
- The router rejects cold, unknown, downloading, failed, and unproven status. No chat call warms the model.
- Native crash, 2.5-second first-token expiry, 5-second inter-token expiry, or 25-second generation expiry invalidate readiness and return the existing request to cloud. Recovery uses bounded backoff.
- Signed locations and user tokens are never persisted in the model manifest or source. The publisher accepts only cryptographically verified GitHub OIDC for this canonical repository, dedicated branch, and exact workflow identity.
- The publisher hashes upstream bytes and a full private Storage readback, verifies Range bytes, then writes a distribution receipt. Phone health and physical acceptance remain separate.
- No manual model import, install, selection, warm, or engine diagnostics are linked from the PLP customer navigation.

## Required physical proof — all initially UNVERIFIED
Bind every row to installed APK SHA256, source SHA, model SHA256, package/version, device/OS, timestamp, and minimized event receipts.
1. Clean installation; open app; normal UI usable without model action.
2. Automatic download; interrupt network halfway; restore; prove Range offset continuation.
3. Exact size/hash, real native health tokens, real local user-prompt tokens.
4. Force-stop/reopen; prove identical private model and zero download bytes; real local tokens again.
5. Disable Wi-Fi/mobile data; real local user-prompt tokens with zero provider request.
6. Restore network; kill only inference service process while a request is running; same request receives actual cloud answer without action.
7. Corrupt/reject a candidate update; previous active file and usable generation survive.
8. Observe thermal/memory admission, cancellation, and first-token/generation deadlines on the representative phone.

## Current external gates
- Provider readback reports Supabase organization plan Free. The approved model is 2,104,932,768 bytes; current Free upload limit is 50 MB. A plan/global file limit that admits the whole object is required. No plan purchase authorized or performed.
- Qwen2.5 3B upstream is qwen-research. Research/evaluation is permitted; commercial license verification is absent. The new manifest route is limited to active owner/admin evaluation. Customer distribution is not certified.
- No connected physical phone execution worker was found. Do not hand out this APK as accepted before the checklist passes.
- Existing Android workflow uses debug signing for internal artifacts. No signing change or store-release claim is included.

## Rollback
Do not overwrite an active file with a download. Keep previous verified version and immutable base d9a60c7867e40d0d86747a9849a35a9f8be9b992. A failed candidate/native trial never changes the active pointer. Revert this isolated branch to restore prior source; do not merge or deploy unrelated branches.
