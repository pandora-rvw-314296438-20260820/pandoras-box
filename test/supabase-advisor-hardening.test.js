'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const migrationPath = path.join(
  root,
  'supabase',
  'migrations',
  '20261010120000_pandora_advisor_hardening_v1.sql'
);
const tsvPath = '/workspace/master-audit/evidence/rls_initplan_policies.tsv';

const expectedPolicyNames = [
  'enterprise_authority_policies_member_select',
  'enterprise_entities_member_select',
  'enterprise_entity_bindings_member_select',
  'enterprise_field_provenance_member_select',
  'enterprise_identity_resolutions_member_select',
  'enterprise_identity_signals_member_select',
  'enterprise_integration_connections_member_select',
  'enterprise_people_member_select',
  'enterprise_relationships_member_select',
  'enterprise_source_records_member_select',
  'enterprise_realtime_signals_member_read',
  'pandora_build_stream_sessions_member_read',
  'pandora_change_impact_assessments_project_read',
  'pandora_build_stream_events_member_live_read',
  'pandora_activity_jobs_owner_read',
  'pandora_intelligence_threads_owner_select',
  'pandora_phone_local_ai_turns_owner_read',
  'pandora_intelligence_messages_owner_select',
  'pandora_activity_events_owner_read',
  'pandora_activity_controls_owner_read',
  'pandora_project_intents_member_insert',
];

function stripComments(sql) {
  return sql.replace(/--.*$/gm, '').replace(/\/\*[\s\S]*?\*\//g, '');
}

test('supabase advisor hardening migration verification', async (t) => {
  await t.test('(a) migration file exists', () => {
    assert.ok(fs.existsSync(migrationPath), `Expected migration to exist at ${migrationPath}`);
  });

  await t.test('(b) contains alter function with search_path = pg_catalog', () => {
    const content = fs.readFileSync(migrationPath, 'utf8');
    const regex = /alter\s+function\s+private\.pandora_plp_billing_money\s*\(\s*bigint\s*\)\s+set\s+search_path\s*=\s*pg_catalog\s*;/i;
    assert.match(
      content,
      regex,
      'Migration must set search_path = pg_catalog on private.pandora_plp_billing_money(bigint)'
    );
  });

  await t.test('(c) exactly one alter policy statement for each of the 21 policy names', () => {
    const content = fs.readFileSync(migrationPath, 'utf8');
    const stripped = stripComments(content);

    if (fs.existsSync(tsvPath)) {
      const tsvContent = fs.readFileSync(tsvPath, 'utf8');
      const tsvLines = tsvContent
        .trim()
        .split('\n')
        .filter((l) => !l.startsWith('#') && l.trim().length > 0);
      const tsvPolicies = tsvLines.slice(1).map((l) => l.split('\t')[1].trim());
      assert.deepEqual(
        tsvPolicies,
        expectedPolicyNames,
        'Expected policy names must match TSV exactly'
      );
    }

    assert.equal(expectedPolicyNames.length, 21, 'Must have exactly 21 expected policies');

    for (const policyName of expectedPolicyNames) {
      const regex = new RegExp(`\\balter\\s+policy\\s+${policyName}\\b`, 'gi');
      const matches = stripped.match(regex) || [];
      assert.equal(
        matches.length,
        1,
        `Expected exactly 1 alter policy statement for ${policyName}, found ${matches.length}`
      );
    }

    const totalAlterPolicyMatches = stripped.match(/\balter\s+policy\b/gi) || [];
    assert.equal(
      totalAlterPolicyMatches.length,
      21,
      `Expected exactly 21 total alter policy statements, found ${totalAlterPolicyMatches.length}`
    );
  });

  await t.test('(d) no bare auth.uid() not wrapped as (select auth.uid())', () => {
    const content = fs.readFileSync(migrationPath, 'utf8');
    const unwrappedFull = content.replace(/\(\s*select\s+auth\.uid\(\)\s*\)/g, '');
    assert.doesNotMatch(
      unwrappedFull,
      /\bauth\.uid\(\)/,
      'Found bare auth.uid() not wrapped as (select auth.uid())'
    );

    const stripped = stripComments(content);
    const unwrappedStripped = stripped.replace(/\(\s*select\s+auth\.uid\(\)\s*\)/g, '');
    assert.doesNotMatch(
      unwrappedStripped,
      /\bauth\.uid\(\)/,
      'Found bare auth.uid() in SQL statements not wrapped as (select auth.uid())'
    );
  });

  await t.test('(e) contains no drop/create/grant/revoke statements', () => {
    const content = fs.readFileSync(migrationPath, 'utf8');
    const stripped = stripComments(content);
    const forbiddenStatementsRegex = /\b(drop|create|grant|revoke)\b/i;
    assert.doesNotMatch(
      stripped,
      forbiddenStatementsRegex,
      'Migration must not contain drop, create, grant, or revoke statements'
    );
  });
});
