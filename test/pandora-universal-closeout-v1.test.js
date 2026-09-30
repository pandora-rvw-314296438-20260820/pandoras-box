"use strict";

const assert=require("node:assert/strict");
const {readFileSync}=require("node:fs");
const {join}=require("node:path");
const {test}=require("node:test");

const closeout=readFileSync(
  join(__dirname,"../supabase/migrations/20260930114000_pandora_universal_closeout_v1.sql"),
  "utf8",
);

test("two-way sync loop prevention is explicit and append-only",()=>{
  assert.match(closeout,/pandora_sync_guard_v1/);
  assert.match(closeout,/opposite_direction_echo_suppressed/);
  assert.match(closeout,/duplicate_source_event/);
  assert.match(closeout,/target_write_digest=p_source_event_digest/);
  assert.match(closeout,/enterprise_sync_receipts/);
});

test("schema transitions fail closed unless exact or explicitly backward-readable",()=>{
  assert.match(closeout,/pandora_schema_compatibility_rules/);
  assert.match(closeout,/pandora_schema_read_compatibility_v1/);
  assert.match(closeout,/compatibility_rule_missing/);
  assert.match(closeout,/supported_version_transition/);
  assert.match(closeout,/breaking_transition/);
});

test("verified reconciliation obeys authority and preserves an immutable decision trail",()=>{
  assert.match(closeout,/pandora_reconcile_verified_field_v1/);
  assert.match(closeout,/incoming_provenance_not_verified/);
  assert.match(closeout,/authority_policy_missing/);
  assert.match(closeout,/incoming_source_matches_authority_policy/);
  assert.match(closeout,/current_authoritative_value_retained/);
  assert.match(closeout,/reconciliation_decisions_are_append_only/);
  assert.match(closeout,/confidence_state='superseded'/);
  assert.match(closeout,/confidence_state='disputed'/);
});

test("provider sunset cannot be silent because dependencies and warning state are inspectable",()=>{
  assert.match(closeout,/pandora_provider_deprecation_notices/);
  assert.match(closeout,/pandora_provider_deprecation_impact_v1/);
  assert.match(closeout,/warningVisible/);
  assert.match(closeout,/readyForSunset/);
  assert.match(closeout,/activeActivations/);
  assert.match(closeout,/requiredPolicyDependencies/);
  assert.match(closeout,/preferredPolicyDependencies/);
  assert.match(closeout,/fallbackPolicyDependencies/);
});

test("new closeout surfaces retain RLS and least-privilege execution boundaries",()=>{
  assert.match(closeout,/enable row level security/);
  assert.match(closeout,/revoke all on function public\.pandora_sync_guard_v1/);
  assert.match(closeout,/revoke all on function public\.pandora_reconcile_verified_field_v1/);
  assert.match(closeout,/grant execute on function public\.pandora_sync_guard_v1[\s\S]*to service_role/);
  assert.match(closeout,/grant execute on function public\.pandora_reconcile_verified_field_v1[\s\S]*to service_role/);
  assert.match(closeout,/revoke update,delete on table public\.enterprise_reconciliation_decisions from service_role/);
});
