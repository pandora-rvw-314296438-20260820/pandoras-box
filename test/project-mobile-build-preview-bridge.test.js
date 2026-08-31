const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const experience = fs.readFileSync('apps/pandora-mobile/lib/core/data/project_experience_api.dart', 'utf8');
const runtimeApi = fs.readFileSync('apps/pandora-mobile/lib/core/data/project_runtime_api.dart', 'utf8');
const models = fs.readFileSync('apps/pandora-mobile/lib/core/models/project_journey_models.dart', 'utf8');
const journey = fs.readFileSync('apps/pandora-mobile/lib/features/simple/project_journey_flow.dart', 'utf8');
const generator = fs.readFileSync('supabase/functions/pandora-project-source-generator/index.ts', 'utf8');
const migration = fs.readFileSync('supabase/migrations/20260829173334_pandora_generated_build_rpc_bridge_v1.sql', 'utf8');

test('mobile Build triggers the provider-blind governed source generator', () => {
  assert.match(experience, /Future<void> requestBuild\(/);
  assert.match(experience, /functions\.invoke\(\s*'pandora-project-source-generator'/s);
  assert.match(experience, /'projectId': projectId/);
  assert.match(experience, /'idempotencyKey': idempotencyKey/);
  assert.doesNotMatch(experience, /Gemini|Vercel|GitHub|GPT/);
});

test('runtime snapshot projects exact candidate and verification truth', () => {
  assert.match(models, /class ProjectRuntimeCandidate/);
  assert.match(models, /required this\.versionId/);
  assert.match(models, /required this\.artifactDigest/);
  assert.match(models, /class ProjectRuntimeVerification/);
  assert.match(models, /required this\.publishEligible/);
  assert.match(models, /final ProjectRuntimeCandidate\? candidate/);
  assert.match(models, /final ProjectRuntimeVerification\? verification/);
});

test('Preview requires the exact built version and artifact digest', () => {
  assert.match(runtimeApi, /required String versionId/);
  assert.match(runtimeApi, /required String artifactDigest/);
  assert.match(runtimeApi, /'versionId': versionId\.trim\(\)/);
  assert.match(runtimeApi, /'artifactDigest': artifactDigest\.trim\(\)\.toLowerCase\(\)/);
  assert.match(runtimeApi, /'idempotencyKey': key/);
  assert.doesNotMatch(runtimeApi, /body: const <String, Object\?>\{\}/);
});

test('Build Theatre advances Build to candidate to exact Preview', () => {
  const buildAt = journey.indexOf('experience.requestBuild(');
  const candidateAt = journey.indexOf('final candidate = snapshot.candidate;');
  const previewAt = journey.indexOf('experience.createPreview(');
  assert.ok(buildAt > 0);
  assert.ok(candidateAt > 0);
  assert.ok(previewAt > candidateAt);
  assert.match(journey, /versionId: candidate\.versionId/);
  assert.match(journey, /artifactDigest: candidate\.artifactDigest/);
  assert.match(journey, /_buildIdempotencyKey/);
  assert.match(journey, /_previewIdempotencyKey\(candidate\)/);
  assert.doesNotMatch(journey, /Gemini|Vercel|GitHub|GPT/);
});

test('source generator reaches private intake only through a service-role public bridge', () => {
  assert.match(generator, /pandora_commit_generated_build_intake_service_20260830/);
  assert.doesNotMatch(generator, /admin\.rpc\("pandora_commit_generated_build_intake_v2_20260829"/);
  assert.match(migration, /create or replace function public\.pandora_commit_generated_build_intake_service_20260830/);
  assert.match(migration, /select private\.pandora_commit_generated_build_intake_v2_20260829/);
  assert.match(migration, /revoke all on function public\.pandora_commit_generated_build_intake_service_20260830[\s\S]+from public, anon, authenticated/i);
  assert.match(migration, /grant execute on function public\.pandora_commit_generated_build_intake_service_20260830[\s\S]+to service_role/i);
});
