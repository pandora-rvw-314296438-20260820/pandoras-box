# Core Pandora Android runtime evidence

This lane exercises the generic/core Pandora package
`com.banataosystems.pandora_mobile`. It consumes an existing canonical Android
artifact and never rebuilds the app. It does not change signing, native ABI,
Android session persistence, provider configuration, or user roles.

## Exact source and APK

The existing `pandora-mobile-integration.yml` is the build authority. Its
`SOURCE_SHA` is the actual checkout, including GitHub's synthetic merge commit
for a pull request. GitHub's workflow `head_sha` can instead be the PR head.

`core_artifact_provenance.py` binds the provider run, artifact, manifest, commit
and tree. For a synthetic merge it also checks that the provider head is a direct
parent of the compiled commit. It rejects expired/ambiguous/wrong-run artifacts,
different build attempts, changed APK bytes, and unsafe archive paths.

The runtime uses the **debug APK by default**, matching the existing publication
lane. A profile APK may provide supplementary performance observations; its
results do not qualify a different debug APK for distribution. The installed
`base.apk` SHA-256 must equal the verified artifact APK before and after the
journey. `aapt` and `apksigner` independently read its package, version, ARM64 ABI,
modern signature verification result and certificate fingerprint. A debug
signature is explicitly recorded and is not promoted to production signing.

## Native execution before merge

`pandora-core-mobile-journey.yml` runs on a canonical-repository PR. It waits for
the separate successful mobile build and resolves the artifact by **compiled
source SHA**, not just PR head. This avoids rebuilding, a circular dependency on
an unfinished build run, and mismatched source/manifest evidence.

The platform lane runs without authentication credentials. Small and tall phone
viewports run sequentially on standard Ubuntu 24.04 GitHub runners with KVM. The
lane verifies the actual device reports ARM64 support before installing the
unchanged ARM64 APK on the Google APIs x86_64 image. Binary translation is
recorded; physical-device and physical-GPU equivalence are not asserted.

The pinned runtime is Android Emulator 37.2.12, platform-tools 37.0.1, Android 35
Google APIs x86_64 image revision 9, Android build-tools 36.0.0, and command-line
tools 19.0. Official archive SHA-256 digests are checked during installation. The
external UIAutomator2 driver is pinned with hashes for CPython 3.12/Linux x86_64.
Its dependency file is `core_runtime/requirements.txt`, a conventional basename
covered by the repository's Dependency review workflow.

An existing build can also be selected with `workflow_dispatch` using
`source_sha`, `build_run_id`, `artifact_id`, `build_kind`, and `mode`. The existing
mobile build workflow already supports dispatching a branch ref. GitHub requires
a new dispatch workflow file on the default branch before that event is a
reliable first-use path; the new runtime workflow therefore has its own PR path.

## Authentication boundary

The ordinary PR lane is `platform`. It never receives the QA login values.
Platform success explicitly sets `runtime_verified=false` and
`continuous_chat_journey_verified=false`.

The authenticated lane requires all of:

1. An independently reviewed exact compiled candidate SHA.
2. The protected GitHub environment `pandora-core-mobile-qa`, with actual required
   reviewers confirmed by a provider readback.
3. Environment variable `PANDORA_CORE_QA_REVIEWED_SOURCE_SHA` equal to that exact
   candidate SHA. A different commit, merge candidate or refreshed PR fails.
4. An existing sanctioned login in environment secrets
   `PANDORA_CORE_QA_EMAIL` and `PANDORA_CORE_QA_PASSWORD`.
5. An explicit authenticated dispatch, or a maintainer applying the
   `core-mobile-qa-reviewed` label after the candidate review. A subsequent PR
   source change uses the ordinary platform lane until separately reviewed.

The environment name alone is insufficient: absent reviewers, missing login or
missing/mismatched SHA causes failure. No user is provisioned, owner role added,
password reset sent, JWT fabricated, browser session extracted, or app session
injected by these tools. A sanctioned existing login or separately authorized
provisioning/handoff must exist before this acceptance gate can run.

The native form performs real Supabase sign-in. Android's deliberate memory-only
Auth policy remains intact. The restart test re-authenticates through that form
and then verifies the same thread and prior context are reconstructed.

## Backend qualification before authenticated execution

The existing mobile build injects source revision and app version. It uses the
core Supabase target from `pandora_config.dart`; selecting a Vercel preview does
not redirect that APK or the Edge function's canonical bridge URL. A successful
platform journey therefore does not establish that the candidate v2 protocol is
deployed or that cancellation, readback and history reconstruction can succeed.

Before authenticated execution, the release operator must bind the reviewed
candidate to authoritative migration, Edge-function and bridge deployment
readbacks. Use reader-before-writer order: deploy the compatible legacy/native-
message streaming bridge and verify its candidate and canonical alias bytes;
then apply the additive v2 database migrations/new issuers; deploy the
v1-compatible v2 Edge bundle; and run the exact-source Android journey.
Existing provider stream permission must be
verified before that bridge can claim streaming readiness. A separately
authorized canonical staging stack can serve this purpose only when its backend
and corresponding APK configuration are actually established and recorded.

This workflow provisions or deploys none of those resources. It also does not
turn a successful older candidate receipt into approval for a changed candidate.
If merging produces a new source SHA or APK, verify and exercise that exact
artifact again before distributing it. Runtime receipts and deployment readbacks
must identify the source and backend versions that were tested together.

## Interaction coverage and its limits

The authenticated driver performs the continuous 39-step core chat sequence
without resetting state, followed by empty submission, rapid send, long
multiline input, cancellation followed immediately by a new turn, repeated model
surface open/close, and process restart with real re-authentication/history
restoration. It uses opaque accessibility identifiers for thread, logical turn,
phase, retry target, composer, navigation and picker controls. It checks Auto and
reasoning selection independently.
The empty draft conversation identity is distinguished from the durable server
thread created at first admission; that one-time binding is accepted, and later
changes are rejected.

The keyboard is the actual installed Android IME. Text is entered using Android
accessibility `ACTION_SET_TEXT`; no alternative keyboard is installed. Hardware
Back closes the IME and drawer. Ctrl+Enter exercises the app's keyboard submission
shortcut. The default IME identity is checked again at the end.

The recoverable failure path verifies that the isolated emulator has no active
default network before submitting one turn. It requires turn-owned uncertainty
with no premature retry, restores connectivity, and invokes the real readback
through Check again. Only verified non-admission may expose Retry for that same
logical turn. This is a real transport recovery test. It does not establish a live
provider outage or exercise a global provider shutdown. Provider-specific
failure/late-callback behavior still needs its relevant contract/runtime evidence.

The history-view race waits for streaming to be active before scrolling upward.
While the newest response is off-screen, completion is observed through the
persistent generation control; the off-screen response is inspected after the
explicit Return to latest action. The driver must not force-scroll history just
to read an off-screen accessibility node.

UI-observed tap-to-acceptance, first observed content, and completion times are
recorded with their measurement context. They are not backend acceptance, routing,
provider-start, or provider TTFT measurements. Android frame and memory metrics
are included when the OS provides them; absent measurements stay absent.
Emulator translation and debug builds limit performance conclusions.

## Evidence privacy and interpretation

The canonical repository is public. Workflow artifacts contain only source/APK
provenance, hashed thread/turn/request/response identifiers, geometry/state
assertion results, durations, and available frame/memory metrics. They do not
contain passwords, tokens, raw chat text, private drawer content, UI hierarchy
dumps, screenshots, or video. UIAutomator transport debug printing and library
logging are disabled before entering credentials.

`--private-evidence <directory>` can retain local screenshots after a new test
conversation has been established. It is explicitly rejected in GitHub Actions.
Credential-filled screens are never captured. A separate authorized private
channel is needed for visual recordings/review; metadata alone does not establish
pixel-level visual acceptance or physical-device behavior.

Receipts distinguish artifact verification, installation, platform interaction,
authenticated continuous runtime interaction, and production verification.
Every tool leaves `production_verified=false`. A missing login, incompatible ABI,
incomplete boot, missing semantic target, failed turn, stale retry, moved history
anchor, changed thread, or changed installed APK fails the relevant gate.

## Local helper checks

```sh
python3 -m unittest discover -s apps/pandora-mobile/tool -p 'core_*_test.py' -v
actionlint -shellcheck='' .github/workflows/pandora-core-mobile-journey.yml
```

These tests exercise evidence boundaries and driver parsing. They are not Android
runtime acceptance and must not be reported as the continuous native journey.
