
const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');

const migrationPath = join(process.cwd(), 'supabase', 'migrations', '20260828181500_pandora_economics_runtime_safety_v1.sql');
const source = readFileSync(migrationPath, 'utf8');

test('Worker A economics and budget contracts are durable and bounded', () => {
  for (const required of ['pandora_budget_limits','pandora_cost_entries','pandora_reserve_budget','pandora_release_budget','pandora_commit_budget']) assert.match(source, new RegExp(required));
  assert.match(source, /reserved_micros \+ spent_micros <= hard_limit_micros/);
  assert.match(source, /pandora_cost_entries_append_only/);
  assert.match(source, /idempotency_key text not null/);
});

test('Worker A project knowledge and runtime isolation stay ProjectSpec scoped', () => {
  for (const required of ['pandora_project_nodes','pandora_project_relationships','pandora_runtime_resources',"isolation_mode in ('dedicated','shared_isolated','logical')",'ProjectOS binding identity mismatch']) assert.ok(source.includes(required), required);
  assert.match(source, /project_spec_id uuid not null references public\.pandora_project_specs/);
});

test('Worker A secret registry stores references only and is service-only', () => {
  const start = source.indexOf('create table if not exists public.pandora_secret_references');
  const end = source.indexOf('create table if not exists public.pandora_database_change_plans');
  assert.ok(start >= 0 && end > start);
  const section = source.slice(start, end);
  assert.doesNotMatch(section, /\b(secret_value|token_value|password_value|credential_value|plaintext_value)\b/i);
  assert.match(section, /reference_locator text not null/);
  assert.match(section, /reference_kind in \('supabase_vault','provider_secret','environment_binding','external_vault'\)/);
  assert.match(source, /revoke all on table public\.pandora_secret_references from public, anon, authenticated/);
  assert.doesNotMatch(source, /grant select on table public\.pandora_secret_references to authenticated/);
});

test('Worker A database changes fail closed on production and destructive execution', () => {
  for (const required of ['pandora_database_change_plans','pandora_database_change_items',"environment <> 'production' or approval_required",'database plan approval action hash mismatch','destructive or production database execution requires backup and rollback plan','database execution requires bound tool-call lineage','verified database plan requires PASS verification']) assert.ok(source.includes(required), required);
  assert.match(source, /pandora_database_change_items_append_only/);
  assert.match(source, /invalid database change state transition/);
});

test('Worker A customer-readable contracts use RLS while secret references stay opaque', () => {
  for (const table of ['pandora_budget_limits','pandora_cost_entries','pandora_project_nodes','pandora_project_relationships','pandora_runtime_resources','pandora_database_change_plans','pandora_database_change_items']) assert.ok(source.includes(`'${table}'`), `missing RLS loop membership for ${table}`);
  assert.match(source, /private\.is_org_member\(organization_id\)/);
  assert.match(source, /alter table public\.pandora_secret_references enable row level security/);
});
