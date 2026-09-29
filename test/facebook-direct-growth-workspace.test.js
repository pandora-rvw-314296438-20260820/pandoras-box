
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const test = require("node:test");

const sql = fs.readFileSync(
  "supabase/migrations/20260930012000_marketing_growth_direct_workspace_v2.sql",
  "utf8",
);
const screen = fs.readFileSync(
  "apps/pandora-mobile/lib/features/enterprise/marketing_growth_workspace_screen.dart",
  "utf8",
);

test("direct growth workspace has no Operations Room execution dependency", () => {
  assert.match(sql, /sourceMode','direct_github'/);
  assert.match(sql, /operationsRoomRequired',false/);
  assert.match(sql, /directGithubSource',true/);
  assert.doesNotMatch(sql, /pandora_ops_tasks|pandora_ops_events|pandora_ops_human_gates/);
});

test("operational lead review is business-only, service-only, and non-spending", () => {
  assert.match(sql, /pandora_growth_lead_reviews/);
  assert.match(sql, /pandora_growth_set_lead_stage_v1/);
  assert.match(sql, /r\.is_test is false/);
  assert.match(sql, /PANDORA_GROWTH_LEAD_REVIEW_SERVICE_ROLE_REQUIRED/);
  assert.match(sql, /stage in \('new','qualified','lost','paid','refunded'\)/);
  assert.match(sql, /'spendAuthorized',false/);
  assert.doesNotMatch(sql, /subject_id.*jsonb_build_object|journey_id.*jsonb_build_object/);
});

test("approved Memory retrieval is receipt-bound and cannot grant authority", () => {
  assert.match(sql, /pandora_growth_memory_retrieval_receipts/);
  assert.match(sql, /status text not null check\(status='approved_current'\)/);
  assert.match(sql, /query_sha256/);
  assert.match(sql, /record_sha256/);
  assert.match(sql, /memoryCanGrantSpend',false/);
  assert.match(sql, /canonicalMemoryWritten',false/);
});

test("experiment registry preserves uncertainty instead of fabricating winners", () => {
  assert.match(sql, /pandora_growth_experiment_runs/);
  assert.match(sql, /'comparisonConditions',r\.comparison_conditions/);
  assert.match(sql, /'uncertainty',r\.uncertainty/);
  assert.match(sql, /'resultSha256',r\.result_sha256/);
  assert.match(screen, /None claimed/);
  assert.match(screen, /Causal claim/);
});

test("owner/admin projection is redacted and consequential actions remain denied", () => {
  assert.match(sql, /v_role not in \('owner','admin'\)/);
  assert.match(sql, /'staffAccess',false/);
  assert.match(sql, /'exportsAllowed',false/);
  assert.match(sql, /'rawPiiVisible',false/);
  assert.match(sql, /'campaignMutationGranted',false/);
  assert.match(sql, /'publishingAuthorized',false/);
  assert.match(sql, /'spendAuthorized',false/);
});

test("Pandora chat receives only bounded read-only growth evidence", () => {
  assert.match(screen, /'mode': 'read_only_analysis'/);
  assert.match(screen, /'evidenceCitationRequired': true/);
  assert.match(screen, /'approvedMemory'/);
  assert.match(screen, /'experimentRuns'/);
  assert.match(screen, /'leadStages'/);
  assert.match(screen, /enterpriseContext: chatContext/);
});
