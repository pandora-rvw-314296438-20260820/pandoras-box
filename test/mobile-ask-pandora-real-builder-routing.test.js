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
