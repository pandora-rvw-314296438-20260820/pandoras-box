# Pandora's-box Full Repository Audit

**Audit date:** 2026-10-14  
**Canonical repository:** `pandora-rvw-314296438-20260820/pandoras-box`  
**Branch / audited HEAD:** `main@f6b3759117db167bf9a2666f55fa290b77f116fe`  
**Scope:** repository governance and layout; CI/release controls; live Supabase inventory and advisors; migration parity; security-sensitive source paths; open PR backlog; deployment/source evidence.  
**Method:** read-only GitHub source review, exact-head Actions readback, Supabase provider metadata and advisor readback. This audit made no app-code, database, policy, secret, or production-setting changes.

## Executive summary

**Release status: NOT PRODUCTION-VERIFIED.** CI is green on the audited SHA, but CI does not prove live production/source parity.

The strongest verified risks are control-plane evidence drift, saturated Edge Function capacity, and unfinished database authorization/replay review. No direct critical exploitable vulnerability or committed plaintext secret was confirmed by this bounded audit.

### Current source and CI

The canonical repository is `pandora-rvw-314296438-20260820/pandoras-box`, default branch `main`, HEAD `f6b3759117db167bf9a2666f55fa290b77f116fe`. Actions readback for that SHA shows successful Node 24, Flutter Android/iOS full validation, mobile exact-source, runtime seams/mobile events, Windows Worker Contract, Push-on-main analysis, Canonical release evidence, and artifact retention. The repo has a substantial verification suite: source-authority policy, TypeScript/browser checks, Supabase syntax/hardening/replay checks, canonical evidence contract, mobile exact-source checks, and dependency review.

Positive controls:
- `vercel.json` sets `git.deploymentEnabled=false`; a main push does not itself claim a production deploy.
- Canonical status docs require `documented → implemented → tested → deployed → productionVerified`, fresh provider evidence, exact source/deployment/rollback binding, trusted independent review and physical-device receipts.
- The reviewed PLP checkout/status functions are restricted to postgres/service_role and have pinned search paths.
- No direct `eval(` search match was found; environment-variable names referencing service-role keys are not plaintext key leaks.

## Findings

### P1 — Supabase Edge Function capacity is saturated

**Evidence:** Live project `jcyqixttuebxqqfkjonq` reported 100 active functions of 100 total. No inactive function is available as headroom. One inventory entry, `pandora-value-meter-v1-20260819`, lacks the source digest field; `pandora-owner-api` is active at v104. The source `supabase/config.toml` deliberately disables bulk Edge deployment because of this provider limit.

**Risk:** new function deployment can fail at the quota, and at least one active function's exact source is not proven by the returned inventory digest.

**Remediation:** reconcile all 100 slugs with live callers, ownership, retention and provider/source evidence; classify each as CORE/BROKER/WEBHOOK/ADMIN/RECOVERY/TEMPORARY/LEGACY/UNRECONCILED; retire only with caller and rollback/retention evidence; record exact source bundle and provider digest. Do not delete by name or age.

### P1 — Release evidence registries and PR triage are stale

**Evidence:** `ops/supabase/hardening/edge-function-lifecycle-registry.json` was observed 2026-09-07; `security-advisor-dispositions.json` was observed 2026-09-01; current advisor output is dated 2026-10-14. `docs/status/OPEN_PR_TRIAGE.json` says repository `banataosystems/Pandoras-box`, base SHA `5a630893f2102064dcb2c7c72a3374042e6b4542`, observation date 2026-08-23 and a 41-PR snapshot. Current canonical policy points to this repository instead.

**Risk:** a process consuming those artifacts as current state may select the wrong repo/base or make decisions against a stale Edge/PR inventory.

**Remediation:** regenerate through provider readback; bind repository, base SHA, observed time and complete counts to the exact current source; preserve old snapshots as historical evidence. Update consumers only with tests rejecting stale/mismatched authorities. Do not blindly merge or archive the queue.

### P1 — SECURITY DEFINER grants need a complete per-function audit

**Evidence:** Supabase security advisor reports 98 public SECURITY DEFINER functions executable by `authenticated`. Direct readback shows this is a review queue, not 98 confirmed vulnerabilities: PLP checkout/status RPCs are service_role-only, while examples such as `begin_phone_local_ai_acceptance`, `capture_phone_local_ai_acceptance`, `create_organization` and `pandora_get_source_entitlement_v1` are authenticated-callable and have `auth.uid()` checks in their source.

**Risk:** SECURITY DEFINER routines run with elevated rights; any missing membership/tenant checks, unsafe dynamic SQL or writable search path could create privilege or cross-tenant problems.

**Remediation:** enumerate every one of the 98 signatures, grants, language, search_path and source; verify owner/admin/org checks, tenant binding, input constraints, replay/idempotency handling and dynamic SQL safety; revoke authenticated execute or use invoker/service-only where public execution is not required. Add wrong-org/non-member/low-role/replay adversarial tests. Do not blanket-revoke legitimate RPCs.

### P1 — Leaked-password protection is disabled

**Evidence:** Supabase security advisor `auth_leaked_password_protection`, WARN count 1.

**Risk:** Auth does not reject passwords identified by the configured breached-password check.

**Remediation:** enable via a controlled provider configuration change; regression-test signup, password update and sign-in; read back the setting and capture evidence.

### P1 — Mutable search path in a privileged function

**Evidence:** advisor identifies `private.pandora_plp_billing_money` as role-mutable `search_path`.

**Risk:** if privileged code resolves unqualified objects through a caller-influenced path, object substitution may be possible. Exploitability depends on grants, language and object qualification.

**Remediation:** inspect exact definition and grants, pin a trusted search path or fully qualify objects, verify untrusted schemas are not writable by callers, test with hostile search_path, and apply via versioned migration with post-deploy advisor/grant readback.

### P1 — Legacy Vercel OIDC identity remains hardcoded in a live control function

**Evidence:** `supabase/functions/mcpmaster-supabase-control/gemini-worker-gateway.mjs` hardcodes issuer/audience/owner/subject with `mbanatao` and environment `development`; `api/gemini-mcp.ts` expects the matching legacy principal. The function is active (v85) in Supabase, while repo README and denylist prohibit operational use of `mbanatao/*`. Legacy host aliases are allowed only for bounded runtime/OAuth continuity pending verified migration.

**Risk:** likely identity/source drift and release-continuity blocker. This is not by itself proof of token forgery or unauthorized access.

**Remediation:** provider-read current Vercel OIDC issuer, audience and signed claim values; migrate gateway and consumer together to verified claims; negative-test wrong issuer, audience, owner, project, environment and Origin; retain old values only for a documented/verified rollback path. Do not guess the replacement issuer.

### P1 — Supabase migration/source replay parity remains unresolved

**Evidence:** main contains 938 migration files. Open PR #1009 records a previous live ledger count of 961 as of its observation and the Supabase Preview error “Remote migration versions not found in local migrations directory.” The live ledger currently includes PayPal migrations through `20261014120829_plp_checkout_include_paypal_payment_method_v1`, beyond the checked-in migration tail. The recent live PLP checkout/status changes were applied through the Vault-backed path, but PR #1019 only records Billing UI/test source and explicitly leaves canonical SQL function-source parity to separate work.

**Risk:** clean replay/Preview may fail; production function definitions cannot reliably be reconstructed from current canonical migration source.

**Remediation:** reconcile every current live ledger version to a canonical immutable migration or explicit history receipt; recover missing statement bytes from exact evidence; validate dependencies/order; run the clean-baseline replay and Supabase Preview before future database deployments. Do not merge the old PR #1011 just to paper over a different runtime state.

### P2 — Legacy CORS origin remains in source defaults

**Evidence:** `supabase/functions/pandora-owner-api/contract.ts` includes `https://mcpmaster-mbanatao-dc676069.vercel.app` beside canonical and Enterprise origins. Policy allows legacy hosts to remain temporarily for runtime/OAuth continuity, but demands current verification.

**Risk:** a stale host expands browser-origin trust if it is no longer under trusted control. CORS is not authorization, so the issue is conditional rather than a confirmed access bypass.

**Remediation:** verify live DNS/alias ownership, OAuth callback callers and runtime source parity; test authorization separately from CORS; remove legacy origins after callers are migrated.

### P2 — Service-role environment binding is inconsistent across functions

**Evidence:** `pandora-meta-oauth`, `pandora-source-files`, `pandora-base44-bridge`, `pandora-owner-api` and parts of `mcpmaster-supabase-control` refer to `SUPABASE_SERVICE_ROLE_KEY`; some code paths also read `SUPABASE_SECRET_KEYS`. These are environment-variable references, not secret values.

**Risk:** config drift can cause deployment failures or inconsistent fallback behavior when Supabase key names/secret binding change.

**Remediation:** document supported key formats per runtime and standardize secret binding in bounded PRs; fail closed if server-only credentials are missing; confirm no weaker/public key fallback is used for privileged operations; test that keys never enter clients, logs, artifacts or migrations.

### P2 — Overlapping permissive RLS policies and per-row auth evaluation

**Evidence:** advisors report 9 multiple-permissive-policy findings and 21 RLS init-plan warnings.

**Risk:** PostgreSQL permissive policies combine with OR semantics, so a broader policy may widen access; repeated per-row auth calls waste resources.

**Remediation:** calculate effective privileges by role/action; add wrong-tenant tests; combine policies only where semantics are equivalent; use advisor-recommended init-plan forms such as `(select auth.uid())` where safe.

### P2 — Historical documents remain easy to mistake for authority

**Evidence:** README and `SOURCE_AUTHORITY_POLICY.json` mark `RECOVERY_STATUS.md` and old `mbanatao/*`/ `banataosystems/Pandoras-box` sources as historical-only, while those legacy names still occur in history documents, the PostHog candidate docs, FlutterFlow delivery provenance and deployment/identity records.

**Risk:** an automated or manual workflow may select old repositories, base SHAs or deployments as current.

**Remediation:** keep integrity-bound snapshots immutable; add prominent historical-only markers where allowed; update nonhistorical operational records; add tests forbidding the legacy owner in current routing, source selection and new-release inputs.

### P2 — Vercel static environment configuration needs a client-boundary check

**Evidence:** `vercel.json` includes static values such as `PANDORA_MEMORY_ALLOW_MUTATIONS=true`, granted Memory scopes and a FlutterFlow project allowlist; token values are intended to remain protected runtime secrets.

**Risk:** if mutation flags are read by the wrong environment or bundled to clients, a server-only capability could be over-enabled. Source inspection alone does not establish deployed Vercel environment semantics.

**Remediation:** verify each consumer is server-side and authorization-gated; ensure values never appear in client bundles or public endpoints; read back actual Vercel environment scopes and compare against source config.

### P3 — Performance debt

**Evidence:** advisors report 440 unindexed foreign keys, 263 unused indexes and the 21 auth init-plan warnings noted above.

**Remediation:** use query statistics and real plans to prioritize high-traffic tables; add FK indexes with lock/build effects planned; do not drop “unused” indexes until statistics duration/reset and uncommon maintenance queries are considered.

### P3 — Open PR backlog needs dependency-aware triage

**Evidence:** open candidates include #1018–#1015, dependent PayPal webhook #1014/#1013, draft/owner-review PLP PR #1011, advisor hardening #1010, migration parity #1009, source recovery #957, chat foundation #950, PLP actions #867, hardening #840 and non-mergeable #793. PR descriptions state dependencies, owner-approval or review constraints.

**Remediation:** refresh all open PR metadata, diffs, exact heads, check suites, approvals, base ancestry and supersession against current main. Preserve required independent review and owner authorization. Do not merge solely because `mergeable=true`.

## Release decision

**Do not label the repo production-verified from green CI alone.** Priority order:

1. refresh the live Edge Function and PR-triage registries;
2. review `private.pandora_plp_billing_money` search_path and enable leaked-password protection;
3. classify all 98 authenticated-executable SECURITY DEFINER RPCs and prove tenant boundaries;
4. reconcile live migration ledger to canonical source and make clean replay/Preview green;
5. verify and migrate the legacy OIDC identity without guessing provider claims;
6. reclaim Edge capacity with caller/retention evidence;
7. capture the canonical exact-source deployment, distinct rollback and physical Android journey receipts.

## Limitations

This is a broad remote/static audit with live provider metadata and advisor checks. I did not clone/run the full repository locally, conduct an external penetration test, probe customer production routes, retrieve secret values, or change production data, grants or settings. “No confirmed P0” means none was proven in this bounded audit, not that no vulnerabilities exist.
