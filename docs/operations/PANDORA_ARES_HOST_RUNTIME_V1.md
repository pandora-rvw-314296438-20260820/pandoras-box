# ARES governed host execution V1

Task: OPS-ARES-HOST-V1-001. Owner: ChatGPT OPS-ARES-HOST-20260926.
Parent: OPS-LIVE-INTEGRATIONS-V2-001; Operations Room issue #714.
Implementation source: pandora-rvw-314296438-20260820/pandoras-box.
Base: b63e3a710534aa530ba26f8a654f60aabc6e7a93, after #728 merged.

## Scope and truth

This increment implements the actual host-side Android SDK execution adapter, signed admission checks, durable local delivery fencing, artifact verification and bounded HTTP receiver. It does not create an enrolled node, a real ChatGPT worker, a new authority policy, an active Supabase endpoint, production deployment, or independent release approval.

ChatGPT authors implementation. ATHENA schedules; existing M3/Tool Gateway authorizes; ARES executes on an enrolled machine; ARTEMIS independently accepts source/runtime results. This node cannot approve itself. RDP is not an LLM host, source authority, or replacement for GitHub.

A real concurrent Router writer was detected in the initial continuation directory. That work was not overwritten. ARES uses a separate worktree/index/branch and only new `workers/pandora-ares/**`, its root-discovered test, and this document. The primary integration worker retains Router, SQL, Sheets and UI ownership. The existing emulator argv foundation remains unchanged.

## Implemented components

| Module | Actual behavior |
| --- | --- |
| contract.mjs | Exact jobs, fixed Pandora package/operation vocabulary, emulator-only serials, bounded argv parameters, profile/source identity and secret rejection. |
| authority.mjs | Pinned Ed25519 public-key verification of exact-action grants; nonce-bound fresh lease/control-revision readback; bounded HTTPS control transport with an injected protected node-signing callback. |
| journal.mjs | Node 24 built-in SQLite WAL delivery journal; independent-process resource exclusion, immutable events/receipts, idempotent replay, retained ambiguous holds and current-daemon managed-instance identity. |
| process.mjs | Real shell-disabled child processes, pinned executable/JAR digests, restricted environment without inherited provider credentials, bounded output/time, actual process evidence. |
| artifact.mjs | Signed exact-source artifact manifest, confined private APK paths, content-addressed private copy, byte digest, aapt package/version/ABI and apksigner certificate verification. |
| host.mjs | Actual emulator start/stop/readiness, APK install/uninstall, target-bound UI actions, instrumentation, runtime permissions, private capture and post-action readback. |
| handler.mjs | Bounded non-browser JSON receiver; signed jobs only, capacity limit, streamed body size/deadline, normalized errors and replay. No network listener is enabled by import. |

No new npm package, root dependency/lock change, production migration, or source-provider credential is required by this increment. Node 24 `node:sqlite` is used for the local delivery journal; the Operations Room's Supabase state remains authoritative.

## Authority and enrollment contract

The trusted node bootstrap constructs `SignedAresProofs` using approved public Ed25519 keys, issuer and node ID. It constructs `AresLeaseAuthority` using an authenticated control-plane transport. Provider master keys, service-role keys, PATs and API keys are never host job arguments or inherited child-process environment variables.

An action grant is a canonical compact JWS with `alg=EdDSA`, a pinned `kid`, and `typ=PANDORA_ARES_GRANT_V1`. Claims bind organization, project, task, worker, node audience, lease, generation, request, operation, exact action hash, source SHA, profile SHA-256, AVD/serial/package, test environment, risk, M3 policy reference, exact approval when destructive, and control revision. Maximum grant lifetime is ten minutes; ordinary jobs are shorter. This transports an existing M3 ALLOW decision. It does not let the node independently grant authority.

Every SDK step rechecks a fresh control-plane lease. The response is a canonical signed `PANDORA_ARES_LEASE_V1` proof with a new nonce, exact scope/action/control revision, running state and evidence reference. Its lifetime is at most thirty seconds and age at use at most fifteen seconds. A stale, revoked, cross-scope or replayed nonce fails closed. The control-plane issuer must additionally bind the original admitted dispatch and one-time M3 action identity; this adapter cannot replace the server's durable action/lease enforcement.

`createHttpsLeaseReader` accepts only the configured Supabase project host and `/functions/v1/pandora-ares-control` path; redirects, URL credentials, query strings, arbitrary domains and plain HTTP are denied. The deadline includes signing, response headers and response body. `signNodeRequest` must use the enrolled machine identity in its protected holder, not a provider master credential. The corresponding server handler and node enrollment are parent integration work; their existence is not asserted here.

The private signed APK manifest has type `PANDORA_ARES_APK_V1` and binds project, artifact reference, source SHA, APK hash, version, signer hash, package, ABIs and exact verification reference. Configure artifact-proof keys separately from execution-grant keys when the verifier/issuer roles differ. The bootstrap must use artifact attestations issued by the actual trusted release path, never a model-generated assertion.

## Profile and machine boundary

Profiles identify exactly one organization/project and synthetic-data-only AVD/serial. Duplicate serials or AVD names cannot be registered in one node. The profile digest includes the entire reviewed profile and pinned SDK-tool catalog, including instrumentation suite artifacts. A signed grant cannot be reused after that configuration changes.

The node must be installed with dedicated OS identity and private ACL-protected journal, artifact cache and evidence directories. No other untrusted user may replace the executable, its dependencies, AVD files or verified artifact between validation and execution. File/path/digest checks are defense in depth, not protection against a compromised administrator or writable SDK DLL directories. No public HTTP listener or firewall rule is created here. Mount the receiver only behind an authorized outbound relay or authenticated private node transport; control-plane consumers must authenticate the node and verify receipt provenance before admitting its events.

Only emulators are accepted. Physical phones, ADB-over-network addresses, arbitrary APK paths, arbitrary shell strings, other packages, global adb resets, unknown-process termination and protected-app actions are denied. An AVD must be independently enrolled as synthetic/test-only; this source does not infer that existing AVD user data is empty or safe.

Only an emulator actually launched by this daemon and matched to its durable managed record/current process handle can be mutated. After a daemon restart, an existing PID is not automatically adopted or killed. Keep its hold and perform trusted reconciliation. Losing a response, expiring a lease, or restarting does not authorize repeating an install or clearing state.

## Implemented operations and proof

- `ares.health.read`: target presence, ADB state, boot-complete property, emulator property, package-manager response, AVD identity and ABI. A successful observation of an absent guest does not mean ready.
- `ares.emulator.start`: reviewed AVD, explicit even port, read-only/no-snapshot cold boot, no host camera, optional headless operation. Real boot/readback gates follow process spawn; process existence is insufficient.
- `ares.emulator.stop`: only a current owned instance, emulator identity readback, ADB emulator kill, then observed absence. No OS-wide PID kill or factory reset.
- `ares.apk.install`: signed artifact plus real package/version/ABI/signer checks, safe `install -r` without downgrade or blanket permission grants, then installed base.apk hash and version readback. Split APKs are intentionally not accepted by this version.
- `ares.apk.uninstall`: exact existing candidate identity, destructive action grant, provider Success and subsequent package absence. Failure remains unverified.
- `ares.ui.test`: exact installed candidate, registered launch component, current target foreground, bounded screen coordinates, safe tap/type/swipe/back and force-stop. This proves execution/readback, not semantic UI acceptance.
- `ares.test.run`: registered exact-source test APK/component, digest-bound test installation and instrumentation. Requires nonzero `OK (N tests)`, final success code and no failure markers; it cannot invent a passing test suite.
- `ares.permission.change`: only the fixed runtime permission allowlist, exact destructive approval and actual granted/revoked package-state readback. SMS, contacts, accessibility and secure-settings permissions are not exposed.
- `ares.evidence.read`: private screenshot/video or bounded target-PID crash evidence from synthetic owned emulators. Raw crash messages and credential-shaped strings are not persisted. Captures are referenced by digest, never embedded in public receipts or semantic Memory.
- `ares.app.clear_data`: requires exact approval. SDK Success is not application-reset verification; it remains `verification_required` and retains the hold.
- `ares.network.configure`: bounded emulator network presets and actual before/after status digests. Command acceptance is not validated bandwidth/latency semantics; it remains `verification_required` pending an independent adapter/assertion.

The last two states are intentional proof gaps, not false completion. Their holds require trusted reconciliation before reuse. No emulator-reset/factory-wipe operation is exposed. A future reset must have a separately defined destructive scope and proof.

## Result, recovery, and Theatre semantics

`executed_and_read_back` means this bounded host operation has local runtime readback. All receipts still state `taskComplete=false`, `releaseVerified=false`, and `physicalDeviceVerified=false`. Only ARTEMIS and the canonical verifier can accept the parent task/release. An instrumentation pass is emulator test evidence, never physical Android acceptance.

The journal stores action digests and redacted receipts, not raw typed text, grant tokens, node signatures, prompts or provider secrets. Each process event is emitted only after real spawn/observation. Ambiguous or insufficiently verified mutations retain resource holds across process boundaries and restarts. Retry with the same request is idempotent; changed input with the same request ID is rejected.

A server outage cancels further steps and fails closed. Timeouts stop only the SDK child owned by that call; they do not prove the Android-side operation stopped. The node may therefore require reconciliation even after its client process exits. There is no blind automatic reset, install retry, journal deletion, or time-only ownership stealing.

`pendingEvents` exposes a bounded sequence for the existing canonical event producer. It is not a new Build Theatre schema or authority. Parent integration must authenticate node events, bind canonical job/generation and persist admission acknowledgement. Do not render a local 'completed' journal state as global COMPLETE or Live.

## Verification and release

Run `node --test test/pandora-ares-host-runtime.test.js`. The existing root `npm test` glob includes this test. It covers signed scope/time/nonce denial; managed-only lifecycle; mock SDK byte/signer/ABI readback; no shell/protected-app widening; actual pinned Node child processes and bounded environment/output/time; actual independent-process SQLite contention; immutable journal; HTTP deadlines; unknown result retention and honest acceptance states.

SDK mock cases are explicitly synthetic. Separate real pinned SDK read-only probes are needed on the authorized node. Live launch/install/UI/instrumentation and physical acceptance are not implied by unit tests. Preserve exact source hashes and actual logs in the release handoff rather than copying stale counts into this document.

Before live activation: qualifying independent exact-source review and CI; reconcile parent operation catalog with existing M3 admission; configure protected node identity/public trust; implement and verify the control-plane lease endpoint and artifact resolver; enroll a truly synthetic AVD; prove exact current-node start/install/test/stop; admit its real events to Build Theatre; test disconnect/revoke/reconnect without duplicate effects; record verified evidence through the existing Memory candidate/review path.

Rollback means pause new node dispatch and preserve journal/ambiguous holds, not delete evidence or kill an unknown emulator. No production Supabase/Vercel deployment is part of this source change.

## Durable lessons

Separate concurrent writers by exact paths, worktree and publisher rather than trusting a shared role name. Readiness requires guest/runtime evidence, not a running process. Signed intent cannot replace fresh lease authority. An SDK Success cannot replace independent application acceptance. Preserve failed and uncertain outcomes; never manufacture completion to free capacity.

Official SDK references: Android Developers `tools/adb`, `tools/apksigner`, `studio/run/emulator-commandline`, and `studio/run/emulator-console`.
