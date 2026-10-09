# PLP Enterprise — PayPal Billing Server Repair Runbook

> **STATUS: DESIGN ONLY — APPROVAL REQUIRED; NOTHING APPLIED OR DEPLOYED.**  
> This runbook documents the server-side fixes for PLP PayPal subscription checkout, reconciliation, and webhook notifications (defects S1–S4). All code changes are staged for review; no production database migrations or edge functions have been applied.

---

## 1. What Is Broken (Defect Evidence)

Audited against production environment `jcyqixttuebxqqfkjonq` (read-only queries and production logs):

| Defect | Issue Description | Production Evidence | Impact |
|---|---|---|---|
| **S1** | **Live checkout always fails.** `public.pandora_plp_billing_checkout_v1` inserts `created_by` instead of `requested_by` into `pandora_paypal_billing_sessions`, omits NOT NULL columns (`plan_code`, `paypal_plan_id`, `return_url`, `cancel_url`), and updates non-existent columns (`error_message`, `provider_reference`). | `postgres_logs` 2026-10-09T19:02:11Z (Oct 10 03:02 PHT): `column "created_by" of relation "pandora_paypal_billing_sessions" does not exist`. `function_edge_logs`: 100% of live `POST /billing/paypal/checkout` requests returned HTTP 400 (`BILLING_REQUEST_FAILED`). 0 billing sessions, 0 subscriptions created. | 100% of checkout attempts fail immediately with "PayPal didn't respond." Nobody can subscribe or pay. |
| **S2** | **Reconciliation fails to activate.** `public.pandora_plp_billing_reconcile_v1` attempts to update session `status = 'provider_verified'`. | Table constraint `pandora_paypal_billing_sessions_status_check` allows only: `('created','approval_pending','active','cancel_requested','cancelled','suspended','expired','failed')`. Violates CHECK constraint. | The entire reconciliation transaction rolls back, preventing subscription activation even after successful PayPal approval. |
| **S3** | **No PayPal webhook receiver deployed.** Production provider config `pandora_runtime_provider_configs.webhook_url` points to `.../pandora-owner-api/billing/paypal/webhook`, which hits owner-api v98 where no webhook route exists (returns 401). | Grep of deployed entry point: 0 webhook routes; 4 rows in `pandora_paypal_billing_webhook_events` are ignored catalog events from 2026-10-08. No background reconciliation cron job. | Activations, recurring renewals, payment failures, suspensions, and cancellations occurring in PayPal are never synced unless manually triggered by an owner. |
| **S4** | **SUSPENDED and EXPIRED states unhandled.** `reconcile_v1` only inspected `ACTIVE` and `CANCELLED`. | Function definition analysis vs PayPal subscription lifecycle states. | Failed recurring payments resulting in suspension leave customer subscriptions marked as active indefinitely. |

---

## 2. What This Changes

### A. Database Migration Phase 1: Checkout Hotfix (`supabase/migrations/20261010090000_plp_billing_checkout_hotfix_v1.sql`)

Shipped first as the smallest, safest unit to repair broken checkout immediately:

1. **`public.pandora_plp_billing_checkout_v1`**:
   - Inserts exact table columns: `organization_id`, `requested_by`, `plan_id`, `plan_code`, `idempotency_key`, `paypal_plan_id`, `status` ('created'), `return_url`, `cancel_url`, `expires_at` (now + 3 hours). Never touches `created_by`, `error_message`, or `provider_reference`.
   - Validates idempotency key (8–128 chars, allowed charset) and HTTPS return/cancel URLs.
   - Takes transaction advisory lock `pg_advisory_xact_lock(hashtextextended('plp-billing-checkout:' || org_id, 0))` to serialise concurrent checkout attempts per organization.
   - Idempotent replay: Reuses unexpired `approval_pending` sessions (`replayed: true`), retries `failed`/`created` sessions, and returns existing status for terminal sessions.
   - Cross-device deduplication: Detects open approval sessions on the same plan and returns them with `replayed: true`.
   - Validates that returned approval URLs strictly use HTTPS and end with `.paypal.com` or equal `paypal.com`.
   - Uses `errcode = '23505'` for `SUBSCRIPTION_ALREADY_ACTIVE` (matching live function behavior).
   - Rolls back whole attempt on provider failure by raising `PAYPAL_CHECKOUT_FAILED` without updating session to `'failed'`, ensuring retries with the same idempotency key start clean and PayPal dedupes on `paypal-request-id = session id`.

2. **`public.pandora_plp_billing_reconcile_v1`**:
   - Fixes session status transition to `'active'` (never `'provider_verified'`).
   - Reference priority: If `v_sub` is null or `v_sub.state = 'cancelled'`, prefers newest session reference (`v_session.paypal_subscription_id`) when created after `coalesce(v_sub.updated_at, '-infinity')`, preventing organizations with replaced/cancelled subscriptions from reconciling old PayPal subscriptions forever; otherwise preserves existing order (`v_sub.provider_reference`, `v_session.paypal_subscription_id`, `v_change.paypal_subscription_id`).
   - On `ACTIVE` readback: Upserts `pandora_customer_subscriptions` with `state = 'active'`, `source_kind = 'provider_verified'`, `request_admission_enabled = true`, and sets `request_admission_started_at = coalesce(existing, now())`.
   - On `SUSPENDED` readback: Sets subscription `state = 'suspended'`, `request_admission_enabled = false`, `request_admission_started_at = null`, and session `status = 'suspended'`.
   - On `CANCELLED` / `EXPIRED` readback: Sets subscription `state = 'cancelled'`, `request_admission_enabled = false`, `ends_on = greatest(current_date, coalesce(starts_on, current_date))`, and session `status = 'cancelled'`.
   - On `APPROVAL_PENDING`: Marks session `'expired'` if past `expires_at`.

3. **`public.pandora_plp_billing_status_v1`**:
   - Preserves identical return structure while mapping `checkout.trust` and `activity.trust` to treat status `'active'` as `'provider'`.
   - Exposes `expires_at` on the checkout session payload.

4. **Function Permissions**:
   - Revokes all permissions from `public`, `anon`, and `authenticated` on the 3 functions.
   - Grants `EXECUTE` exclusively to `service_role` and `postgres`.

### B. Database Migration Phase 2: Webhook Ingest & Reconcile Cron (`supabase/migrations/20261010091000_plp_paypal_webhook_ingest_v1.sql`)

Depends on Migration A. Applying it alone changes nothing user-visible until the edge function is deployed and PayPal is re-pointed:

1. **`private.pandora_paypal_verify_webhook_v1(p_headers jsonb, p_raw_body text)`**:
   - Performs server-side cryptographic signature verification via PayPal API `POST /v1/notifications/verify-webhook-signature`.
   - Uses exact raw body bytes (`p_raw_body text`) rather than re-serialized jsonb (which reorders keys and causes byte-sensitive PayPal signature verification failures). Builds the request payload text by trimming the final `'}'` from `jsonb_build_object(...)::text` and appending `, "webhook_event": ` || `p_raw_body` || `'}'`.
   - Validates required PayPal transmission headers and pins PayPal certificate URLs to `api(-m)(\.sandbox)?\.paypal.com`.
   - Uses Vault secret `paypal_webhook_id` and service bearer token. Secrets are never exposed or logged.

2. **`public.pandora_plp_paypal_webhook_ingest_v1`**:
   - Validates maximum raw body size (≤ 128 KB) and executes signature verification before any database insert or state change.
   - Stores SHA-256 payload digest and minimal projected JSON payload (strips buyer PII, emails, shipping addresses).
   - Resolves organization by subscription ID, provider reference, or session custom UUID.
   - For `BILLING.SUBSCRIPTION.*` and `PAYMENT.SALE.*` events, delegates state synchronization strictly to `reconcile_v1(org, null)` (never derives subscription state from event names).
   - Returns 200 on success/duplicates, 401 on invalid signature, 400 on invalid body, and 500 on transient processing failures to ensure PayPal delivery retries.

3. **`private.pandora_plp_billing_reconcile_open_v1` and Cron Schedule**:
   - Automatically checks up to 20 organizations with pending approvals (< 3 days) or stale verified subscriptions (> 20 hours old).
   - Replay-safely registers a 10-minute recurring schedule `pandora-plp-billing-reconcile-v1` via `pg_cron` when enabled.

4. **Function Permissions**:
   - Revokes all permissions from `public`, `anon`, and `authenticated` on all 3 functions.
   - Grants `EXECUTE` on public functions exclusively to `service_role` and `postgres`.

### C. Deno Edge Function (`supabase/functions/pandora-plp-paypal-webhook/index.ts`)
- Standalone webhook endpoint operating without user JWT (`verify_jwt = false`).
- Enforces HTTP `POST` only (405), payload length ≤ 131,072 bytes (413), and presence of the 5 `paypal-*` transmission headers (400).
- Forwards lower-case signature headers and raw text body to RPC `pandora_plp_paypal_webhook_ingest_v1`.
- Never logs request headers or raw bodies; logs only structured `{ code }`.

### D. Gateway Configuration (`supabase/config.toml`)
- Configures `[functions.pandora-plp-paypal-webhook]` with `verify_jwt = false` (deployment is an owner-approved manual step: `supabase functions deploy pandora-plp-paypal-webhook --no-verify-jwt`).

---

## 3. Apply Order (Deployment Runbook)

Execute in exact sequence upon receiving authorized owner approval:

1. **Owner Approval Gate**:
   - Verify approval signature for PR implementing SPEC B.
   - Ensure credentials exist in Supabase Vault: `paypal_client_id`, `paypal_client_secret`.

2. **Phase 1: Apply Hotfix Database Migration (A First, Independently)**:
   - Repairs broken live checkout (defects S1, S2, S4) immediately:
   ```bash
   # Execute via Supabase SQL Editor:
   supabase/migrations/20261010090000_plp_billing_checkout_hotfix_v1.sql
   ```
   - Rollback target if needed: `supabase/rollback/20261010090000_plp_billing_checkout_hotfix_v1.down.sql` (exact live snapshot).

3. **Phase 2: Apply Webhook Ingest Database Migration (B)**:
   - Applies webhook functions, background reconcile helper, and pg_cron schedule (changes nothing user-visible until edge function is deployed):
   ```bash
   # Execute via Supabase SQL Editor:
   supabase/migrations/20261010091000_plp_paypal_webhook_ingest_v1.sql
   ```
   - Rollback target if needed: `supabase/rollback/20261010091000_plp_paypal_webhook_ingest_v1.down.sql`.

4. **Phase 3: Deploy Webhook Edge Function**:
   ```bash
   supabase functions deploy pandora-plp-paypal-webhook --no-verify-jwt
   ```
   Live Endpoint URL:
   `https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-plp-paypal-webhook`

5. **Phase 4: Register & Re-point Webhook in PayPal Developer Dashboard**:
   - Navigate to **PayPal Developer Dashboard** → **Apps & Credentials** → **PLP Enterprise (Live)** → **Webhooks**.
   - Click **Add Webhook** (or re-point existing URL).
   - URL: `https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-plp-paypal-webhook`
   - Select Event Types:
     - `BILLING.SUBSCRIPTION.ACTIVATED`
     - `BILLING.SUBSCRIPTION.UPDATED`
     - `BILLING.SUBSCRIPTION.SUSPENDED`
     - `BILLING.SUBSCRIPTION.CANCELLED`
     - `BILLING.SUBSCRIPTION.EXPIRED`
     - `BILLING.SUBSCRIPTION.PAYMENT.FAILED`
     - `PAYMENT.SALE.COMPLETED`
     - `PAYMENT.SALE.REFUNDED`
     - `PAYMENT.SALE.REVERSED`
   - Save and copy the generated **Webhook ID** (e.g., `WH-XXXXXXXXXXXXXXXXX`).

6. **Phase 5: Store Webhook ID in Vault and Update Provider Config**:
   ```sql
   -- Insert or update webhook id in Vault
   insert into vault.decrypted_secrets (name, decrypted_secret)
   values ('paypal_webhook_id', '<PAYPAL_WEBHOOK_ID>')
   on conflict (name) do update
   set decrypted_secret = excluded.decrypted_secret;

   -- Update runtime provider config webhook URL
   update public.pandora_runtime_provider_configs
   set config_value = 'https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-plp-paypal-webhook',
       updated_at = now()
   where provider = 'paypal' and config_key = 'webhook_url';
   ```

---

## 4. Verification Queries

Run the following SQL queries to verify system health after application:

### A. Verify Function Definitions & Grants
```sql
select routine_name, routine_type, security_type
from information_schema.routines
where specific_schema in ('public', 'private')
  and routine_name in (
    'pandora_plp_billing_checkout_v1',
    'pandora_plp_billing_reconcile_v1',
    'pandora_plp_billing_status_v1',
    'pandora_paypal_verify_webhook_v1',
    'pandora_plp_paypal_webhook_ingest_v1',
    'pandora_plp_billing_reconcile_open_v1'
  );
```

### B. Verify Checkout Session Insertion
```sql
select id, organization_id, plan_code, status, paypal_subscription_id, approval_url, expires_at, created_at
from public.pandora_paypal_billing_sessions
order by created_at desc
limit 5;
```

### C. Verify Subscription Activation & Admission Anchor
```sql
select organization_id, plan_id, state, request_admission_enabled, request_admission_started_at,
       source_kind, provider_reference, verified_at, updated_at
from public.pandora_customer_subscriptions
order by updated_at desc
limit 5;
```

### D. Verify Webhook Ingestion & Deduplication
```sql
select provider_event_id, event_type, paypal_subscription_id, organization_id,
       processing_status, processing_error, received_at, processed_at
from public.pandora_paypal_billing_webhook_events
order by received_at desc
limit 10;
```

### E. Verify Scheduled pg_cron Job
```sql
select jobid, jobname, schedule, command, active
from cron.job
where jobname = 'pandora-plp-billing-reconcile-v1';
```

---

## 5. Rollback Plan

If unexpected anomalies occur after deployment:

1. **Phase 2 (Webhook Ingestion & Background Cron) Rollback**:
   - Execute `supabase/rollback/20261010091000_plp_paypal_webhook_ingest_v1.down.sql` to unschedule `pandora-plp-billing-reconcile-v1` and drop the 3 webhook functions.
   - Disable or remove the webhook endpoint URL in the **PayPal Developer Dashboard**.
   - Delete the webhook secret from Vault if webhook processing must be suspended:
     ```sql
     delete from vault.decrypted_secrets where name = 'paypal_webhook_id';
     ```

2. **Phase 1 (Checkout Hotfix) Rollback**:
   - Execute `supabase/rollback/20261010090000_plp_billing_checkout_hotfix_v1.down.sql` (verbatim snapshot of previous live functions).
   - **Caution**: The previous `pandora_plp_billing_checkout_v1` and `pandora_plp_billing_reconcile_v1` functions were fundamentally broken (failed 100% of checkouts with SQLSTATE 42703 on `created_by` and rollbacked reconciles on CHECK constraint violation). Reverting to them will reinstate defects S1 and S2.
   - Any emergency rollback should target only the webhook ingestion functions (`supabase/rollback/20261010091000_plp_paypal_webhook_ingest_v1.down.sql`) while keeping the corrected column names and constraint fixes for checkout and reconcile.
