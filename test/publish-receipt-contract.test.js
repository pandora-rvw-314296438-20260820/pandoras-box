import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const migration = readFileSync(
  resolve(root, "supabase/migrations/20260901093000_pandora_publish_receipts_v1.sql"),
  "utf8",
);

test("publish receipt ledger captures exact provenance and rollback pointer before CAS", () => {
  assert.match(migration, /create table if not exists public\.pandora_publish_receipts/);
  assert.match(migration, /version_id uuid not null references public\.pandora_project_versions/);
  assert.match(migration, /preview_verification_run_id text not null/);
  assert.match(migration, /production_verification_run_id text/);
  assert.match(migration, /previous_production_version_id uuid/);
  assert.match(migration, /previous_production_deployment_id uuid/);
  assert.match(migration, /production_result_url text/);
  assert.match(migration, /select e\.current_version_id, e\.current_deployment_id/);
  assert.match(migration, /after insert on public\.pandora_project_deployments/);
  assert.match(migration, /PUBLISH_RECEIPT_VERIFICATION_REQUIRED/);
});

test("production verification finalizes the same exact receipt and fails closed if missing", () => {
  assert.match(migration, /after update of verification_state, verification_ref, url, immutable_url/);
  assert.match(migration, /new\.verification_state = 'live_verified'/);
  assert.match(migration, /production_verification_run_id = new\.verification_ref/);
  assert.match(migration, /and r\.production_deployment_id = new\.id/);
  assert.match(migration, /and r\.version_id = new\.version_id/);
  assert.match(migration, /PUBLISH_RECEIPT_MISSING/);
});

test("receipt readback is membership-scoped while the ledger remains service-role-only", () => {
  assert.match(migration, /enable row level security/);
  assert.match(migration, /revoke all on public\.pandora_publish_receipts from anon, authenticated/);
  assert.match(migration, /grant select, insert, update, delete on public\.pandora_publish_receipts to service_role/);
  assert.match(migration, /create or replace function public\.pandora_get_publish_receipts/);
  assert.match(migration, /m\.user_id = v_user_id/);
  assert.match(migration, /m\.status = 'active'/);
  assert.match(migration, /grant execute on function public\.pandora_get_publish_receipts\(uuid, integer\) to authenticated, service_role/);
});
