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
  assert.equal(source.includes('handoff.projectId == null'), true);
  assert.equal(source.includes('initialIntent: handoff.request'), true);
});

test('legacy progress remains fallback-only instead of the primary new-build path', () => {
  const realRoute = source.indexOf('if (dependencies.projectExperienceRepository != null)');
  const legacyRoute = source.indexOf("_submissionKey ??= _keys.create('simple-intake')");
  assert.ok(realRoute >= 0);
  assert.ok(legacyRoute > realRoute);
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
  assert.equal(workspace.includes('unawaited(_requestChange(initialChange))'), true);
});
