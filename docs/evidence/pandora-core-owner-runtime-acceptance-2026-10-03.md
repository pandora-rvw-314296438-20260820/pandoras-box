# Pandora Core: corrections from the authenticated owner journey

## Exact boundary

This continuation starts from canonical main `593d8f5db34da6fc727c0449e807174cd3d9835a`, which was serving on Vercel deployment `dpl_9CTGq1Qn8YWzppZ5DcR3UAkWE9oT`. The earlier implementation, migration-history alignment, CI and deployment are preserved. Source existence and a READY deployment did not establish owner acceptance.

The owner signed in to the canonical production origin. Actual use exposed the defects below. This document records the resulting bounded correction; it does not certify the new candidate's browser, customer or physical-device acceptance.

## Observed failures and corrections

| Observed in the real owner flow | Correction |
|---|---|
| Several enabled Core actions, inputs and invitation-menu labels were almost invisible against the dark canvas. | Build the Core theme from Pandora's canonical dark theme, with explicit action and input states. Keep PLP content under its own porcelain theme and the shared composer under Core. |
| PLP Team administration described the platform operator as a customer owner and repeated page chrome. | Preserve the existing authorization RPC's operator classification, use the validated client name, and embed the existing Team screen with one effective refresh. Membership and authorization remain separate. |
| Needs You demanded authorization for credentialless public APIs whose historical evidence was stale or partial. | Reuse a strict private assessment of the trusted manifest, selected account, scopes, capabilities, receipt identity, freshness and Vault marker. Only genuine human authorization requirements enter the decision queue. Stale evidence does not become healthy. |
| Old Operations markers appeared as approvals even though no current decision operation existed; a spending marker related to a subsequently stopped pilot. | Exclude these markers from actionable Needs You. Preserve tasks, historical gates and stopped-pilot authority without restarting work or authorizing spending. |
| Operations events and approved Memory returned HTTP 503 before user authorization. | Preserve native ESM loading through the actual CommonJS Vercel build, using fixed traced paths. Exercise the emitted API rather than only its service modules. Keep authentication, scope, payload and redaction boundaries. |
| Models displayed old Sheets, GitHub and Vercel capability metrics. | Read the current conversational Bedrock catalog using the exact effective routing predicate. Separate configured eligibility, dated runtime results and evidence freshness. No paid probes or routing changes. |
| Audit, operator and usage rows used generic labels or misleading verification badges. | Present the actual action, role, scope, model, measured requests/tokens and available cost classification. Missing financial evidence remains unknown. |
| A correct attention answer immediately disappeared when the frontend automatically opened Clients. | Keep inspection navigation as an explicit answer action, preserve it in history, synchronize visible chat state with the shell, and expose assistant text to accessibility. Preserve the underlying tenant context and explicit action flows. |
| The PLP retry regression triggered Flutter's Future-returning setState assertion. | Change only the two refresh callbacks to void block bodies. Active PLP branch changes remain separate. |
| The same promoted deployment appeared again as the latest candidate. | Deduplicate only the Simple list when both exact source SHA and deployment identity match; retain the audit observations and conflicting or distinct evidence. |

## Hosted database readback

The single forward migration was applied once as `20261003124340_pandora_core_owner_decision_health_v1` on `jcyqixttuebxqqfkjonq`. Its 23,787 SQL bytes have SHA-256 `8de51dd0108c38487f5828c2c516503e2d1077d943545d5eed54cf7744560e7d`. Only the previously unpublished filename and its test reference were aligned to the provider-assigned version; the SQL bytes did not change.

At `2026-10-03T12:44:17.713263Z`, provider readback verified all eight expected function observations: seven changed/new bodies and the unchanged routing dependency, including their ACLs, security modes, volatility and search paths. Migration history contained 933 versions. Six exact prior-body fences and absent-helper checks had passed before application.

No table, RLS policy, index, credential, routing policy or account membership was added or changed by this migration. The two new helpers are private SECURITY INVOKER functions with no anon, authenticated or service-role EXECUTE grant. Existing exposed RPC authorization remains in force.

Post-migration Supabase advisors added no findings: security remained 311 and performance 726, with the same finding identities. These totals include inherited warnings; they are not a claim that the whole database is free of findings.

## Actual owner evidence before correction

- PLP onboarding verification completed at `12:07:48Z`, audit receipt `20116`, operation receipt `8444d425-53e2-484b-9767-bd44a173f33a`. Existing identity, administrator and capability configuration were verified; missing connections, routing, limits, billing and go-live remained pending. No invitation or permission change was made.
- The attention command at `12:30:20.731Z` used platform-scoped thread `a269191d-322f-40bf-8aa9-2c8cace2d3b2`. Its response used `pandora_core` / `deterministic-core-owner-v1`, zero tokens, no model-run record and a completed activity job. The correct response persisted in history despite the frontend navigation defect.
- Customer workspace entry was disabled for the current owner without a customer membership. Manage Client remained a separate authorized control-plane flow. No access was self-granted to complete testing.
- Empty-client validation and cancellation worked without creating a demonstration customer. Client usage, connections, deployment and financial empty states remained explicit.

## Session and acceptance boundaries

Reload returned to sign-in. Canonical commit `2704ec3e4b3e267eedc4c48913aed6c64fc410d5` deliberately removed web session persistence; Core still uses Supabase `EmptyLocalStorage`. This is verified inherited implementation history, not a retrieved owner approval for the production UX. This correction does not weaken that security boundary or store credentials. A new sign-in is required to exercise a reloaded candidate.

Local SQL verification passed 115 tests with no failures or skips, plus a complete 933-migration PostgreSQL/PGlite replay. `provider_equivalence=false` remains explicit. The API regressions run the actual emitted handlers under normal Node and with synchronous require(ESM) disabled, with inert fixture credentials and stubbed transport. Final source-bound widget, CI, deployment and runtime receipts belong to the associated PR/release evidence.

The frozen correction passed 4,361 Node tests with one existing optional skip, plus all 52 worker tests, with the test process explicitly using UTC. All 134 Flutter tests passed across 16 files, including submitted and restored inspection replies, drawer Back retaining the tenant, stale scope callbacks, Team revocation, actual PLP Retry, contrast and existing Ask/PLP regressions. All 13 Dart source/test files were byte-identical before and after the run. Analyzer results were zero errors, three pre-existing Ask warnings and 23 informational findings; the same three warnings were reproduced at exact base `593d8f5`. The analyzer exit code was 1, not a clean analyzer pass. Flutter tooling telemetry was explicitly disabled using its supported flags after an initial automatic approval rejection; the interrupted run was excluded from acceptance.

Final acceptance still requires the corrected deployed owner journey, a genuine customer session, deliberate tenant-denial checks, and any applicable physical-device release evidence. A successful build-time Memory canary imports native modules directly and cannot substitute for the human-facing API test. No production-readiness claim is made here.

## Recovery

Keep the previous immutable deployment as the Vercel rollback target. This additive migration has no data migration to reverse. If a database correction is required, use a reviewed forward migration with exact prior function definitions; do not delete migration history or customer data. Restoring the old queue/reconciler bodies would also restore the diagnosed defects.

## Subsequent source and installed-app corrections

Provider readback at `2026-10-03T14:54:55Z` still showed main `593d8f5db34da6fc727c0449e807174cd3d9835a` and PR 946 head `68e38909ab1a60721363d32f994c6f1695e6ada8`. All six required checks passed. The applicable PLP installed-Android check remained failed and was retained as a release blocker.

The bounded emulator startup correction had worked: the exact-head run booted in 47 seconds, installed the APK and launched PLP. The next failure came from legacy `uiautomator dump` omitting Android's native `hintText`, where the pinned Flutter version places field labels and validation messages. A self-targeted CI instrumentation helper now observes native accessibility metadata for the exact PLP package. It does not start the application, type, sign in or mutate sessions. Input values and descriptions are redacted; capture size, node count, traversal depth and observation time are bounded. The existing assertions still require real Email/Password hints, an obscured password field, enabled Sign in, actual empty-submit validation and successful restart. Screenshots and crash-buffer checks remain separate evidence. Host tests and the actual Flutter sign-in semantics probe passed; native SDK compilation and installed-APK verification belong to the next exact-source CI run.

The workflow now calls the unauthenticated restart observation `unauthenticated_restart_returns_to_sign_in`, with `authenticated_session_restore_tested=false`. It cannot prove authenticated session restoration. This deliberately converges with the identical evidence correction in open PR 868 at `7edb49d2127e359c1cd2bf1e9d52e5a9f12f05fa`; its session/logout implementation and test-list changes remain outside this PR.

The additional owner-surface corrections preserve authoritative distinctions:

- Releases separate deployment readiness from runtime, owner and customer verification. Evidence displays its recorded kind, client scope and date without acquiring an invented verification state.
- Models show Auto and meaningful counts by default, with local disclosure for dated technical evidence. No model selection, routing-policy mutation or paid probe was introduced.
- Automations use the canonical recorded task title and organization name. Missing titles stay missing; task identifiers remain available in detail.
- Live Connections separates pending, successful-empty, query-miss and failed reads. A failed retry cannot display a fabricated empty result.
- Safety gives negative and unknown evidence precedence over healthy terms; missing, stale and failed reads cannot produce a healthy aggregate. Saved Evidence clears failed or invalidated reads, fences account/repository replacement, and labels the current-session cache and oldest observation truthfully.
- More and its secondary pages preserve their inherited theme. An owner content Navigator keeps these pages under the single persistent conversation layer. Visible Back, drawer selection and chat expansion are separate operations. A pinned Flutter callback behavior required guarding the disabled nested pop handler itself so dismissing expanded chat cannot also pop Settings. Client entry and return keep their existing scope reset and isolated client Navigator.

The corresponding focused runs passed 63 Core/Plugins/More Flutter tests, 14 Safety/Evidence Flutter tests, three Plugins source-contract tests and 146 Python tooling tests. The seven UI follow-up Dart files and four Safety/Evidence files analyzed without issues. These local results do not substitute for a newly deployed authenticated journey.

The owner scope suite passed all 21 tests, including the five new actual-control navigation flows and 16 existing tenant/authentication/runtime-boundary tests. A further 21 shared navigation, route-boundary and More tests passed. The new coverage uses real visible Back and system Back rather than directly invoking a public minimize method. Route-animation timing was corrected in test helpers without weakening the retained-page, conversation or tenant assertions. The four navigation source/test files have zero analyzer errors or warnings and eight existing shell style informational findings; the informational exit status remains disclosed.

### Automation-title migration readback

The additional forward migration was applied once through the Supabase migration API as `20261003145650_pandora_core_automation_titles_v1`. Its 2,276 bytes have SHA-256 `db5df496f4d61bb98b889d9fc5debd8021c381aaeae2e42bf876b43449cedcd0`. It replaces only the Automations projection in `public.pandora_core_snapshot_v1(text,uuid)`, fenced by the exact previous function-body digest.

The hosted replacement body has SHA-256 `680d53f83bb7e0268d131e5c2873fc61f179c974f5fcfc911bed55fe028ecabb`. Ownership, existing EXECUTE grants, SECURITY DEFINER, STABLE and empty search path remain unchanged. All 124 Operations task rows have the same full-row digest before and after: `bf0e9753ebd347e3fc3005a64b590e155f12d3d4e986d94bdc8cef94ed923479`. Source and hosted history have exactly 934 matching migration version/name pairs. This is a read-only projection correction; it changes no execution history, authority, routing policy, task or customer data.

After this second migration, advisors again retained exactly the same 311 security and 726 performance finding identities, with zero added or removed. All 33 focused title/projection regression tests passed after filename alignment, and the complete 934-migration replay passed with chain digest `b2dd262276064baf8afbc5d4adce2d37a3d45be302671a1462d309f397e37110`. Local replay still explicitly reports `provider_equivalence=false`; hosted metadata, function bytes and task data were read back independently.

### Existing candidate runtime evidence

Unpromoted Vercel deployment `dpl_BmWXvgRW5i4gN6x5z5iKB9kc3JWc` at source `accf27adfdf8b833464c2f6022860f8eaaeff67b` returned the matching served source manifest and HTTP 200 health. Actual compiled Operations and Memory endpoints returned the expected 405/401/403 denials at `13:52:51Z`, replacing the earlier pre-authorization 503s. The build-time Memory canary verified context availability and a readback-matched pending-review outcome, without canonical approval or a paid model probe. This candidate is evidence for those API repairs, not the later UI changes, merged source or canonical production acceptance. The final promoted SHA, runtime observations and authenticated journeys must be recorded separately.
