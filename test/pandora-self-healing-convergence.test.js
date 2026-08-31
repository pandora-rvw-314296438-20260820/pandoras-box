const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');

const root = join(__dirname, '..');
const migration = readFileSync(
  join(root, 'supabase', 'migrations', '20260830233000_pandora_self_healing_source_convergence_v1.sql'),
  'utf8',
);
const projectionPatch = readFileSync(
  join(root, 'supabase', 'migrations', '20260830235000_pandora_self_healing_projection_state_patch_v2.sql'),
  'utf8',
);
const worker = readFileSync(
  join(root, 'supabase', 'functions', 'pandora-source-convergence-worker', 'index.ts'),
  'utf8',
);
const generator = readFileSync(
  join(root, 'supabase', 'functions', 'pandora-project-source-generator', 'index.ts'),
  'utf8',
);
const mobile = readFileSync(
  join(root, 'apps', 'pandora-mobile', 'lib', 'features', 'simple', 'project_experience_v2.dart'),
  'utf8',
);
const config = readFileSync(join(root, 'supabase', 'config.toml'), 'utf8');

test('active ProjectSpecs converge without an open mobile screen', () => {
  assert.match(migration, /create table if not exists public\.pandora_source_generation_queue/i);
  assert.match(migration, /reason='active_spec'/);
  assert.match(migration, /pandora-auto-spec:/);
  assert.match(migration, /pandora-source-generation-convergence-v1/);
  assert.match(migration, /\* \* \* \* \*/);
  assert.match(migration, /net\.http_post/);
  assert.match(migration, /limit 3\s+for update skip locked/i);
  assert.match(projectionPatch, /owner_state='building'/);
  assert.doesNotMatch(projectionPatch, /owner_state='working'/);
});

test('self-healing is bounded and Worker E acceptance proof remains authoritative', () => {
  assert.match(migration, /j\.error_code='VERIFICATION_FAILED'/);
  assert.match(migration, /c\.check_key='acceptance_requirements'/);
  assert.match(migration, /select count\(\*\)[\s\S]*?c\.status='FAIL'[\s\S]*?\) = 1/);
  assert.match(migration, /where prior_repairs < 2/);
  assert.match(migration, /reason='acceptance_repair'/);
  assert.match(worker, /independentVerificationFailures/);
  assert.match(worker, /Repair those failures without weakening, deleting, bypassing, or reinterpreting acceptance requirements/);
  assert.match(worker, /SUPERSEDED_BY_NEWER_BUILD/);
});

test('source generation preserves the exact verified product baseline', () => {
  assert.match(worker, /loadBaseSource/);
  assert.match(worker, /MAX_BASE_CONTEXT_BYTES = 120 \* 1024/);
  assert.match(worker, /existingVerifiedSource: priorSource/);
  assert.match(generator, /loadLatestVerifiedSource/);
  assert.match(generator, /existingVerifiedSource: priorSource/);
  assert.match(generator, /exact previously verified source snapshot/i);
});

test('workspace questions use Pandora intelligence while explicit changes survive routing outages', () => {
  assert.match(mobile, /_tryIntelligenceTurn\(request\)/);
  assert.match(mobile, /PandoraDependencies\.of\(context\)\.intelligence/);
  assert.match(mobile, /\.chat\(message: request, projectId: widget\.project\.id\)/);
  assert.match(mobile, /if \(turn\.intent == 'chat'\)/);
  assert.match(mobile, /_intelligenceReply = turn\.reply;/);
  assert.match(mobile, /var actionRequest = request;/);
  assert.match(mobile, /intentText: actionRequest/);
  assert.match(mobile, /intentKind: 'change'/);
  assert.doesNotMatch(mobile, /intentText: text\.trim\(\),\s*intentKind: 'change'/);
});

test('internal worker has a one-purpose fail-closed authorization boundary', () => {
  assert.match(config, /\[functions\.pandora-source-convergence-worker\]\s*verify_jwt = false/);
  assert.match(config, /\[functions\.pandora-project-source-generator\]\s*verify_jwt = true/);
  assert.match(migration, /pandora_source_worker_internal_20260831/);
  assert.match(migration, /pandora_validate_source_worker_key_20260831/);
  assert.match(worker, /x-pandora-internal-key/);
  assert.match(worker, /validated\.data !== true/);
  assert.match(worker, /return response\(\{ ok: false, state: "rejected" \}, 401\)/);
});
