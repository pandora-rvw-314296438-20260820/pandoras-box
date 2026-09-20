'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const repositoryRoot = path.join(__dirname, '..');
const migrationPath = path.join(
  repositoryRoot,
  'supabase',
  'migrations',
  '20260817130000_pandora_memory_full_capacity_context_gate.sql',
);
const rollbackPath = path.join(
  repositoryRoot,
  'docs',
  'supabase',
  'recovery',
  'jcyqixttuebxqqfkjonq',
  'rollback',
  '20260817130000_restore_pandora_memory_v1_gate.sql',
);
const priorMigrationPath = path.join(
  repositoryRoot,
  'supabase',
  'migrations',
  '20260807083337_pandora_memory_lifecycle_enforcement.sql',
);
const sql = fs.readFileSync(migrationPath, 'utf8');
const rollbackSql = fs.readFileSync(rollbackPath, 'utf8');
const priorMigrationSql = fs.readFileSync(priorMigrationPath, 'utf8');

const requiredSections = [
  'adaptive_profile',
  'style_profile',
  'project_context',
  'people_context',
  'risk_warnings',
  'open_loops',
  'latest_context_pack',
  'daily_context_pack',
  'recent_events',
  'semantic_matches',
  'canonical_records',
  'approved_record_count',
  'requested_canon_statuses',
  'retrieval_mode',
  'retrieval_reasoning_summary',
  'warnings',
];

function memoryGateDefinition(source) {
  const match = source.match(
    /create or replace function private\.enforce_execution_plan_memory_context\(\)[\s\S]*?\n\$\$;/,
  );
  assert.ok(match, 'Pandora Memory execution gate definition is missing');
  return match[0];
}

test('full-capacity context gate preserves v1 while accepting only contract-verified v2', () => {
  assert.match(sql, /v_schema_version not in \('1\.0\.0', '2\.0\.0'\)/);
  assert.match(sql, /if v_schema_version = '2\.0\.0' then/);
  assert.match(sql, /capabilityContract,status.*'verified'/s);
  assert.match(sql, /capabilityContract,id.*'pandora-pandora-memory-puzzle'/s);
  assert.match(sql, /capabilityContract,version.*'1\.0\.0'/s);
  assert.match(sql, /capabilityContract,schemaVersion.*'1\.0\.0'/s);
  assert.match(sql, /pandora-pandora-memory-contract-v1\.json/);
  assert.match(sql, /banataosystems\/pandoras-box-memory/);
  assert.match(sql, /https:\/\/pandorasbox-memory\.vercel\.app/);
  assert.match(sql, /capabilityContract,compatible.*'true'/s);
  assert.match(sql, /capabilityContract,utilizationPercentage.*'100'/s);
  assert.match(sql, /capabilityContract,semanticHash.*\^\[0-9a-f\]\{64\}\$/s);
  assert.match(sql, /fallbackRequired.*'false'/s);
});

test('full-capacity context gate requires the exact sixteen Memory sections', () => {
  for (const section of requiredSections) {
    assert.match(sql, new RegExp(`"${section}"`));
  }
  assert.match(sql, /jsonb_array_length\(v_required_sections\) <> jsonb_array_length\(v_expected_sections\)/);
  assert.match(sql, /v_required_sections @> v_expected_sections and v_expected_sections @> v_required_sections/);
  assert.match(sql, /jsonb_array_length\(v_observed_sections\) <> jsonb_array_length\(v_expected_sections\)/);
  assert.match(sql, /v_observed_sections @> v_expected_sections and v_expected_sections @> v_observed_sections/);
  assert.match(sql, /jsonb_array_length\(v_missing_sections\) <> 0/);
});

test('full-capacity context gate proves bounded consumption and approved-only canonical retrieval', () => {
  for (const key of [
    'adaptiveProfile',
    'styleProfile',
    'projectContext',
    'peopleContext',
    'riskWarnings',
    'openLoops',
    'latestContextPack',
    'dailyContextPack',
    'recentEvents',
    'semanticMatches',
    'canonicalRecords',
    'approvedRecords',
  ]) {
    assert.match(sql, new RegExp(`'${key}'`));
  }
  for (const key of [
    'adaptive',
    'style',
    'project',
    'people',
    'risks',
    'openLoops',
    'latestContextPack',
    'dailyContextPack',
    'recent',
    'semantic',
    'canonical',
  ]) {
    assert.match(sql, new RegExp(`'${key}'`));
  }
  assert.match(sql, /jsonb_array_length\(v_context\.context_envelope->'warnings'\) > 10/);
  assert.match(sql, /jsonb_array_length\(v_context\.context_envelope->'highlights'->v_highlight_key\) > 3/);
  assert.match(sql, /retrieval,requestedCanonStatuses.*'\["approved"\]'::jsonb/s);
  assert.match(sql, /retrieval,approvedRecordCount.*counts,approvedRecords/s);
});

test('full-capacity migration preserves the existing execution safety boundary', () => {
  assert.match(sql, /new\.status <> 'executing'/);
  assert.match(sql, /plan_id = new\.id/);
  assert.match(sql, /organization_id = new\.organization_id/);
  assert.match(sql, /request_id = new\.request_id/);
  assert.match(sql, /queryBasis,tool.*new\.tool/s);
  assert.match(sql, /context_hash, ''\)\) !~ '\^\[0-9a-f\]\{64\}\$'/);
  assert.match(sql, /new\.risk = 'read'/);
  assert.match(sql, /context_status not in \('available', 'empty'\)/);
  assert.match(sql, /context_status is distinct from 'available'/);
  assert.match(sql, /new\.created_at - interval '10 minutes'/);
  assert.match(sql, /clock_timestamp\(\) \+ interval '1 minute'/);
  assert.match(sql, /recorded_at < new\.created_at - interval '2 seconds'/);
  assert.match(sql, /security definer/i);
  assert.match(sql, /set search_path = ''/);
});

test('rollback artifact restores the exact prior v1 Memory execution gate', () => {
  assert.match(rollbackSql, /TESTED DATABASE ROLLBACK FOR 20260817130000/);
  assert.match(rollbackSql, /not an active migration/);
  assert.equal(
    memoryGateDefinition(rollbackSql),
    memoryGateDefinition(priorMigrationSql),
  );
  assert.match(rollbackSql, /schemaVersion' <> '1\.0\.0'/);
  assert.doesNotMatch(rollbackSql, /2\.0\.0/);
  assert.doesNotMatch(rollbackSql, /capabilityContract/);
});
