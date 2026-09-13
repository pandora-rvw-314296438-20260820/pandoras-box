import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const migrationPath = new URL(
  '../supabase/migrations/20260913102500_pandora_chat_speech_act_routing_v12.sql',
  import.meta.url,
);

const migration = await readFile(migrationPath, 'utf8');

test('selected-project execution is gated by a speech act, not incidental action words', () => {
  assert.match(migration, /pandora_chat_project_request_mode_v1/);
  assert.match(migration, /workspace execution requires an explicit imperative\/request/i);
  assert.match(migration, /project_intelligence_direct/);
  assert.match(migration, /repository_audit_direct/);
  assert.match(migration, /requestMode/);
  assert.doesNotMatch(migration, /v_mutating\s*:=/);
});

test('the exact physical-device planning regression can never be workspace execution', () => {
  assert.match(
    migration,
    /Okay great generate the comprehensive detailed step by step plan on how we are going to build this','project_intelligence'/,
  );
  assert.match(
    migration,
    /Show me the entire detailed plan for this project','project_intelligence'/,
  );
  assert.match(migration, /Build me a step-by-step plan for this project','project_intelligence'/);
  assert.match(migration, /How are we going to build this\?','project_intelligence'/);
  assert.match(migration, /How should we deploy this\?','project_intelligence'/);
  assert.match(migration, /Update me on the project status','project_intelligence'/);
});

test('explicit execution remains distinct from planning and read intent', () => {
  assert.match(migration, /'Build it','workspace_action'/);
  assert.match(migration, /'Please fix this','workspace_action'/);
  assert.match(migration, /'Can you build it now\?','workspace_action'/);
  assert.match(migration, /'Implement the plan','workspace_action'/);
  assert.match(migration, /'Build the app according to the plan','workspace_action'/);
  assert.match(migration, /'Review the entire repo and then fix it','workspace_action'/);
  assert.match(migration, /'Create a plan and then build it','workspace_action'/);
});

test('provider actions remain with the governed capability router instead of workspace heuristics', () => {
  assert.match(migration, /'Deploy it now','default'/);
  assert.match(migration, /'Publish this now','default'/);
  assert.match(
    migration,
    /return public\.pandora_chat_universal_dispatch_v8\([\s\S]*p_organization_id,p_message,p_thread_id,p_project_id[\s\S]*\);/,
  );
});

test('migration replay executes the routing matrix as a database contract', () => {
  assert.match(migration, /do \$speech_act_contract\$/);
  assert.match(migration, /pandora_chat_speech_act_contract_failed/);
  assert.match(migration, /private\.pandora_chat_project_request_mode_v1\(v_case\.message\)/);
});
