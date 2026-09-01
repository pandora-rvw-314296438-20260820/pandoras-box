const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const migration = fs.readFileSync('supabase/migrations/20260902004500_pandora_change_impact_assessment_v1.sql', 'utf8');
const fast = fs.readFileSync('supabase/functions/pandora-project-source-generator/index.ts', 'utf8');
const converged = fs.readFileSync('supabase/functions/pandora-source-convergence-worker/index.ts', 'utf8');
const boundary = fs.readFileSync('packages/pandora-tools/src/cross-worker.js', 'utf8');
const pipeline = fs.readFileSync('workers/pandora-builder/src/execution/build-pipeline.mjs', 'utf8');

test('change impact is derived from exact governed ProjectSpec lineage', () => {
  assert.match(migration, /previous_spec_id/);
  assert.match(migration, /PROJECT_SPEC_IMPACT_PREVIOUS_LINEAGE_INVALID/);
  assert.match(migration, /impact_tier between 0 and 4/);
  assert.match(migration, /v_data_changed or v_database_deployment_changed/);
  assert.match(migration, /v_integration_changed or v_non_database_deployment_changed/);
  assert.match(migration, /v_component_changed/);
  assert.match(migration, /v_brand_changed/);
  assert.match(migration, /conservativeFallback/);
  assert.match(migration, /pandora_bind_build_impact_v1/);
});

test('low-impact generation reuses a complete verified baseline without dropping untouched source', () => {
  for (const source of [fast, converged]) {
    assert.match(source, /pandora_project_change_impact_service_v1/);
    assert.match(source, /full_candidate/);
    assert.match(source, /allFiles/);
    assert.match(source, /merged\.set\(path, content\)/);
    assert.match(source, /authoritative low-impact incremental change/i);
  }
  assert.match(converged, /row\.reason === "active_spec"/);
  assert.match(converged, /repairFeedback\.length === 0/);
});

test('client cannot forge a narrower Worker D impact plan and compile remains independent', () => {
  assert.match(boundary, /delete argumentsForWorker\.change_impact/);
  assert.match(boundary, /trusted\.change_impact/);
  assert.match(pipeline, /validateImpactPlan\(request\.arguments\?\.change_impact\)/);
  assert.match(pipeline, /impact_classified/);
  assert.match(pipeline, /selectVerificationDefinitions/);
  assert.match(pipeline, /const build = await buildProject\(\{[\s\S]*?adapter,[\s\S]*?workspaceRoot/);
  assert.match(pipeline, /runAdapterTests\(\{[\s\S]*?tests: testDefinitions/);
});
