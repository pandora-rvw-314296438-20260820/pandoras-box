const test = require('node:test');
const assert = require("node:assert/strict");
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(
  path.join(process.cwd(), 'apps/pandora-mobile/lib/features/simple/ask_pandora_screen.dart'),
  'utf8',
);

test('Ask Pandora fallback stays universal when intelligence is unavailable', () => {
  assert.equal(source.includes("import 'project_create_experience.dart';"), false);
  assert.equal(source.includes("_keys.create('simple-intake')"), true);
  assert.equal(source.includes('final receipt = await dependencies.repository.ask('), true);
  assert.equal(source.includes('initialIntent: objective'), false);
});

test('ProjectOS handoffs are admission receipts and are never submitted twice', () => {
  assert.equal(source.includes('message: handoff.request'), false);
  assert.equal(source.includes("_keys.create('intelligence-handoff')"), false);
  assert.equal(source.includes('doing so would create duplicate work under a different idempotency key'), true);
  assert.equal(source.includes('initialIntent: handoff.request'), false);
});

test('Ask Pandora never presents the static prototype as a real build result', () => {
  assert.equal(source.includes("import 'build_preview_flow.dart';"), false);
  assert.equal(source.includes('BuildProgressScreen('), false);
});

test('existing-project intelligence handoffs stay in Pandora Chat without a second mutation', () => {
  assert.equal(source.includes('message: handoff.request'), false);
  assert.equal(source.includes('projectId: handoff.projectId'), false);
  assert.equal(source.includes('ProjectWorkspaceV2Screen('), false);
  assert.equal(source.includes('initialChange: handoff.request'), false);
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
  assert.equal(workspace.includes('idempotencyKey ??'), true);
  assert.equal(workspace.includes('idempotencyKey: changeIdempotencyKey'), true);
});
