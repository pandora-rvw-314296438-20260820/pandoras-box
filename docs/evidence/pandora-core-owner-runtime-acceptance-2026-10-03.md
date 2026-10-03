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
