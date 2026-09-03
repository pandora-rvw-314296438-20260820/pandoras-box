const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(
  path.join(process.cwd(), 'apps/pandora-mobile/lib/features/simple/ask_pandora_screen.dart'),
  'utf8',
);

test('Ask Pandora routes new build intents into the real project experience when available', () => {
  assert.equal(source.includes("import 'project_create_experience.dart';"), true);
  assert.equal(source.includes('dependencies.projectExperienceRepository != null'), true);
  assert.equal(source.includes('CreateProjectExperienceScreen('), true);
  assert.equal(source.includes('initialIntent: objective'), true);
});

test('intelligence handoffs without an existing project enter the real create-understand-build journey', () => {
  assert.equal(source.includes('handoffProjectId == null || handoffProjectId.isEmpty'), true);
  assert.equal(source.includes('initialIntent: handoff.request'), true);
});

test('Ask Pandora never presents the static prototype as a real build result', () => {
  assert.equal(source.includes("import 'build_preview_flow.dart';"), false);
  assert.equal(source.includes('BuildProgressScreen('), false);
});


test('existing-project intelligence handoffs enter the real workspace change engine', () => {
  assert.equal(source.includes('final snapshot = await experience.runtime(handoffProjectId);'), true);
  assert.equal(source.includes('ProjectWorkspaceV2Screen('), true);
  assert.equal(source.includes('initialChange: handoff.request'), true);
});

const workspace = fs.readFileSync(
  path.join(process.cwd(), 'apps/pandora-mobile/lib/features/simple/project_experience_v2.dart'),
  'utf8',
);

test('workspace consumes an initial Ask Pandora change only after the authoritative projection allows change', () => {
  assert.equal(workspace.includes('final String? initialChange;'), true);
  assert.equal(workspace.includes('next.canChange'), true);
  assert.equal(workspace.includes('unawaited(_requestInitialChange(initialChange))'), true);
});

test('routed initial changes retry safely with one stable admission key per workspace attempt', () => {
  assert.equal(workspace.includes('bool _initialChangeSubmitting = false;'), true);
  assert.equal(workspace.includes('String? _initialChangeIdempotencyKey;'), true);
  assert.equal(workspace.includes('idempotencyKey: _initialChangeIdempotencyKey'), true);
  assert.equal(workspace.includes('if (_error == null && !_changing) _initialChangeSubmitted = true;'), true);
  assert.equal(workspace.includes('final changeIdempotencyKey ='), true);
  assert.equal(workspace.includes('idempotencyKey ??'), true);
  assert.equal(workspace.includes('idempotencyKey: changeIdempotencyKey'), true);
});
