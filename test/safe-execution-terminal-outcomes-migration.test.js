"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");

const source = readFileSync(join(
  __dirname,
  "..",
  "supabase",
  "migrations",
  "20260823150000_add_safe_execution_terminal_outcomes.sql",
), "utf8");
const rollback = readFileSync(join(
  __dirname,
  "..",
  "docs",
  "supabase",
  "recovery",
  "jcyqixttuebxqqfkjonq",
  "rollback",
  "20260823150000_remove_safe_execution_terminal_outcomes.sql",
), "utf8");

test("terminal plan readback exposes classification but never raw provider payloads", () => {
  assert.match(source, /create or replace function private\.execution_terminal_outcome/i);
  assert.match(source, /'terminalOutcome', private\.execution_terminal_outcome/i);
  assert.match(source, /'terminalClassification', classification/i);
  assert.match(source, /'automaticRetryAllowed', false/i);
  assert.match(source, /'retryContract', retry_contract/i);
  assert.match(source, /'reconciliationRequired', reconciliation_required/i);
  assert.match(source, /'payloadHash', payload_hash/i);
  assert.match(source, /'idempotencyIdentityHash', idempotency_identity_hash/i);
  assert.doesNotMatch(source, /'error'\s*,\s*plan\.error/i);
  assert.doesNotMatch(source, /'resultSummary'\s*,\s*plan\.result_summary/i);
});

test("terminal outcome helper is private and status-only unknown failures require reconciliation", () => {
  assert.match(
    source,
    /revoke all on function private\.execution_terminal_outcome\(text, text, jsonb\)[\s\S]*from public, anon, authenticated, service_role/i,
  );
  assert.match(source, /classification := 'failed_unknown'/i);
  assert.match(source, /provider_outcome := 'ambiguous'/i);
  assert.match(source, /retry_contract := 'reconcile_before_retry'/i);
  assert.match(source, /reconciliation_required := true/i);
});

test("rollback restores the prior list shape and removes only the derived helper", () => {
  assert.match(rollback, /create or replace function public\.list_execution_plans/i);
  assert.doesNotMatch(rollback, /terminalOutcome/i);
  assert.match(
    rollback,
    /drop function if exists private\.execution_terminal_outcome\(text, text, jsonb\)/i,
  );
  assert.doesNotMatch(rollback, /delete from|truncate|drop table/i);
});
