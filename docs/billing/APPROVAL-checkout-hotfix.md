# APPROVAL ITEM — PLP checkout production hotfix (migration A only)

Status: **NOT APPLIED.** Prepared 2026-10-10 PHT by the Order 2 worker. Needs explicit owner approval before anyone runs step 2.

## 1. What is broken (evidence)
- Every owner checkout fails in production. Live `public.pandora_plp_billing_checkout_v1` (md5 of `pg_get_functiondef` = `ab1e404da8e68ba2913f8bfd7dba00f2`) inserts into `pandora_paypal_billing_sessions(created_by, …)`. That column does not exist, and the insert leaves out the NOT NULL columns `requested_by, plan_code, paypal_plan_id, return_url, cancel_url`.
  - Postgres log 2026-10-09T19:02:11Z (Oct 10 03:02 PHT): `column "created_by" of relation "pandora_paypal_billing_sessions" does not exist` (SQLSTATE 42703).
  - Owner-api: all 8 `POST /billing/paypal/checkout` calls in the 24h window failed (400), with 0 successes.
  - Live table state (read-only, 06:50 PHT today): 0 checkout sessions, 0 customer subscriptions, 0 verified-active subscriptions. Nobody has paid and nobody holds access, so no customer row is at risk.
- Even after a checkout worked, activation would also fail. Live `pandora_plp_billing_reconcile_v1` (md5 `4555d1f377d2024c13b9687a2630c0aa`) sets session `status = 'provider_verified'`. That violates `pandora_paypal_billing_sessions_status_check`, so the whole reconcile rolls back and the owner never unlocks.

## 2. What the fix is
File: `supabase/migrations/20261010090000_plp_billing_checkout_hotfix_v1.sql` (PR branch `grok/plp-conversion-checkout`. Use the copy at the PR head SHA.)
- It contains only `CREATE OR REPLACE` of three existing functions. Their signatures, argument names, return keys (`status, approvalUrl, providerReference, replayed, verified` / `verified, label, reason, providerState, providerReference`) and error codes are the same as today. Owner-api v100 (`paypal-billing.mjs`) maps errors by message prefix, so it needs no change.
  - `pandora_plp_billing_checkout_v1`: inserts the real columns. It adds a per-org advisory lock, same-key replay, reuse of an open approval from another device, a 3h approval expiry, and an https-only `paypal.com` approval-host check. If PayPal fails, the whole attempt rolls back, so a retry with the same key starts clean. PayPal also dedupes on `PayPal-Request-Id` = session id.
  - `pandora_plp_billing_reconcile_v1`: sets session `active` (allowed by the CHECK). It handles ACTIVE / SUSPENDED / CANCELLED / EXPIRED and sets `request_admission_enabled`. For a new subscription after a cancellation, it reads the newest session reference.
  - `pandora_plp_billing_status_v1`: the same as live, except checkout/activity `trust` treats session status `active` as provider, and it exposes `expires_at`.
- No table, constraint, data, cron, grant-widening, edge-function or PayPal-config changes. EXECUTE stays limited to `postgres, service_role` (anon/authenticated are revoked).
- Not included (separate approval, see §7): migration B `20261010091000_plp_paypal_webhook_ingest_v1.sql`, edge function `pandora-plp-paypal-webhook`, cron, PayPal webhook re-point.

Offline evidence (PGlite on a replica of the live schema, `/workspace/checkout/sqltest/run.mjs`):
- A alone: 14/14 checks pass (checkout, same-key replay, cross-device reuse, failure rollback + retry, approval-host allowlist, reconcile pending/active/cancelled/re-subscribe, status, grants, replay-safe re-apply).
- A + B: 20/20 pass.
- The rollback file restores the exact live bodies. A rehearsal of the rollback caught a parameter-default incompatibility, which was fixed before this item was written.

## 3. Pre-flight (read-only; stop if anything differs)
```sql
-- 3a. Live bodies are still the ones we snapshotted (if md5s differ, someone changed them: STOP and re-review)
select p.proname, md5(pg_get_functiondef(p.oid))
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in
 ('pandora_plp_billing_checkout_v1','pandora_plp_billing_reconcile_v1','pandora_plp_billing_status_v1')
order by 1;
-- expect: checkout ab1e404da8e68ba2913f8bfd7dba00f2 | reconcile 4555d1f377d2024c13b9687a2630c0aa | status 1f7a1edbeac89fc88349a1a0982ce7af

-- 3b. Migration not already recorded
select version, name from supabase_migrations.schema_migrations where version = '20261010090000';  -- expect 0 rows
```

## 4. Apply (only after approval) — ONE of:
- **Supabase MCP / dashboard:** `apply_migration` on project `jcyqixttuebxqqfkjonq` with name `plp_billing_checkout_hotfix_v1` and query = the full file content at the PR head SHA. This records it in `schema_migrations`.
- **psql:** `psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 --single-transaction -f supabase/migrations/20261010090000_plp_billing_checkout_hotfix_v1.sql`, then
  `insert into supabase_migrations.schema_migrations(version, name) values ('20261010090000','plp_billing_checkout_hotfix_v1');`
- **Do NOT use `supabase db push`.** It would also push migration B, which is not approved.

## 5. Verify (right after apply)
```sql
-- 5a. Bodies changed, defect strings gone, signatures unchanged
select p.proname, pg_get_function_identity_arguments(p.oid) args, md5(pg_get_functiondef(p.oid)) md5,
       position('created_by' in p.prosrc) > 0 as still_created_by,
       position('''provider_verified'', updated_at' in p.prosrc) > 0 as still_bad_session_status,
       p.prosecdef as security_definer, p.proconfig
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in
 ('pandora_plp_billing_checkout_v1','pandora_plp_billing_reconcile_v1','pandora_plp_billing_status_v1');
-- expect: same args as before (no defaults), new md5s, still_* = false, security_definer = true, search_path pg_catalog,public,private

-- 5b. Grants
select p.proname,
  has_function_privilege('anon', p.oid, 'execute') anon,
  has_function_privilege('authenticated', p.oid, 'execute') authed,
  has_function_privilege('service_role', p.oid, 'execute') service
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname like 'pandora_plp_billing_%_v1';
-- expect anon=false, authed=false, service=true for the three functions

-- 5c. Status read (no PayPal call): two plans, provider configured
select jsonb_array_length(r->'plans') plans, r->'provider'->>'configured' configured, r->'subscription' sub
from (select public.pandora_plp_billing_status_v1('076a9306-5c4e-4d9d-98d3-e3a6fea968fb') r) x;
-- expect plans = 2, configured = true, sub = null

-- 5d. Input guard (no PayPal call, wrapped in a rollback)
begin;
select public.pandora_plp_billing_checkout_v1('076a9306-5c4e-4d9d-98d3-e3a6fea968fb', null, 'launch', 'x', 'https://a', 'https://b');
-- expect ERROR ACTOR_REQUIRED (raised before any HTTP)
rollback;
```
5e. End-to-end, owner-performed (creates a PayPal approval but **no payment**):
1. Sign in as the owner on enterprise-omega-five.vercel.app, open Billing, choose Launch, and tap Continue to PayPal.
2. Expect: the PayPal approval page loads.
3. On PayPal, choose "Cancel and return". Do not approve.
4. Then check:
```sql
select status, plan_code, paypal_subscription_id is not null has_ref, expires_at > now() open
from public.pandora_paypal_billing_sessions order by created_at desc limit 3;   -- expect approval_pending, launch, true, true
```
   Also: Postgres logs have no new 42703, and owner-api logs show `POST /billing/paypal/checkout` with status 200.
   The unapproved PayPal subscription stays APPROVAL_PENDING at PayPal and is never billed.

## 6. Rollback (only if A causes a NEW error class; this brings back the broken checkout)
```bash
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/rollback/20261010090000_plp_billing_checkout_hotfix_v1.down.sql
```
(The file is the verbatim live snapshot, wrapped in begin/commit. It is also at `/workspace/checkout/server-ref/live-functions-20261010.sql`.)
```sql
delete from supabase_migrations.schema_migrations where version = '20261010090000';
-- verify: 3a md5s are back to ab1e404d… / 4555d1f3… / 1f7a1edb…
```
If a checkout session was created between apply and rollback, leave it in place. The old functions ignore it, and it expires on its own.

## 7. Related approval items (separate; not part of this hotfix)
1. Migration B `20261010091000_plp_paypal_webhook_ingest_v1.sql`: webhook ingest, PayPal signature verification on the raw body, a `*/10` reconcile sweep via pg_cron. pg_cron 1.6.4 is installed live, so the schedule will be created.
2. Deploy edge function `pandora-plp-paypal-webhook` (verify_jwt = false; signature is checked against PayPal).
3. In the PayPal developer dashboard, re-point the live webhook to `https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-plp-paypal-webhook`. Store its id in Vault `paypal_webhook_id` and update `pandora_runtime_provider_configs` paypal `webhook_url`. Today the webhook goes to owner-api, which returns 401.
4. Owner-api source parity: the deployed v100 runtime patch is not on `main` (S5, flagged to Order 1).
5. Product decision: on cancel, access currently ends when the cancellation is confirmed. The alternative is to keep access until the paid period ends.
6. PostHog build defines (`PANDORA_POSTHOG_HOST`, `PANDORA_POSTHOG_PROJECT_KEY`) so funnel events actually send.
