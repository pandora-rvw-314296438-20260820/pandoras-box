const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');

const root = join(__dirname, '..');
const read = (...parts) => readFileSync(join(root, ...parts), 'utf8');

const repository = read(
  'apps', 'pandora-mobile', 'lib', 'core', 'data',
  'project_experience_repository.dart',
);
const runtimeApi = read(
  'apps', 'pandora-mobile', 'lib', 'core', 'data', 'project_runtime_api.dart',
);
const runtimeEdge = read(
  'supabase', 'functions', 'pandora-project-runtime', 'index.ts',
);
const simpleSources = [
  'project_create_experience.dart',
  'project_experience_v2.dart',
  'project_iteration_experience.dart',
  'project_journey_flow.dart',
].map((name) => read(
  'apps', 'pandora-mobile', 'lib', 'features', 'simple', name,
));

test('one repository owns the customer Project Experience contract', () => {
  for (const method of [
    'createProject(',
    'loadExperience(',
    'watchExperience(',
    'submitIntent(',
    'submitChange(',
    'understanding(',
    'requestBuild(',
    'findBuildStreamId(',
    'loadExactPreviewFiles(',
    'runtime(',
    'createPreview(',
    'undo(',
    'publish(',
    'rollback(',
  ]) {
    assert.ok(repository.includes(method), `missing ProjectExperienceRepository method ${method}`);
  }
  assert.ok(repository.includes('CompositeProjectExperienceRepository'));
  assert.ok(repository.includes('_projection.load(projectId)'));
  assert.ok(repository.includes('_projection.watch(projectId)'));
  assert.ok(repository.includes("intentKind: 'change'"));
  assert.ok(repository.includes('_runtime.rollback('));
});

test('Simple project flows do not coordinate separate project transports', () => {
  for (const source of simpleSources) {
    assert.equal(source.includes('.projectRuntime;'), false);
    assert.equal(source.includes('.projectExperience;'), false);
    assert.equal(source.includes('.projectExperienceProjection;'), false);
  }
  assert.ok(simpleSources.some((source) => source.includes('.projectExperienceRepository;')));
});

test('governed rollback is reachable through the mobile and server contracts', () => {
  assert.ok(runtimeApi.includes("['projects', projectId, 'rollback']"));
  assert.ok(runtimeApi.includes("routeTemplate: '/projects/:id/rollback'"));
  assert.ok(runtimeApi.includes("'targetVersionId': targetVersionId.trim()"));
  assert.ok(runtimeApi.includes("'expectedProductionVersionId': expectedProductionVersionId.trim()"));
  assert.ok(runtimeEdge.includes('const rollbackMatch = route.match(/^\\/projects\\/([^/]+)\\/rollback$/);'));
  assert.ok(runtimeEdge.includes('await rollbackProject(context, decodeURIComponent(rollbackMatch[1]), await bodyJson(req))'));
  assert.ok(runtimeEdge.includes('pandora_authorize_production_rollback_20260831'));
  assert.ok(runtimeEdge.includes('ROLLBACK_APPROVAL_REQUIRED'));
});
