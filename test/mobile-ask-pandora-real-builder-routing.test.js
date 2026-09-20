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

test('Pandora handoffs are admission receipts and are never submitted twice', () => {
  assert.equal(source.includes('message: handoff.request'), false);
  assert.equal(source.includes("_keys.create('intelligence-handoff')"), false);
  assert.equal(source.includes('owns exactly one dispatch'), true);
  assert.equal(source.includes('initialIntent: handoff.request'), false);
});

test('Ask Pandora never presents the static prototype as a real build result', () => {
  assert.equal(source.includes("import 'build_preview_flow.dart';"), false);
  assert.equal(source.includes('BuildProgressScreen('), false);
});

test('explicit selected-project changes execute through the real builder without leaving chat', () => {
  assert.equal(source.includes('message: handoff.request'), false);
  assert.equal(source.includes("handoff?.source == 'project_workspace_change'"), true);
  assert.equal(source.includes('experience.loadExperience(handoffProjectId)'), true);
  assert.equal(source.includes("projection.state.name == 'build'"), true);
  assert.equal(source.includes("idempotencyKey: '$executionKey:initial-build'"), true);
  assert.equal(source.includes('Build started with Gemini.'), true);
  assert.equal(source.includes('projection.activeBuildJobId != null'), true);
  assert.equal(source.includes('experience.submitChange('), true);
  assert.equal(source.includes('experience.understanding('), true);
  assert.equal(source.includes('experience.requestBuild('), true);
  assert.equal(source.includes('ProjectWorkspaceV2Screen('), false);
  assert.equal(source.includes('initialChange: handoff!.request'), false);
  assert.equal(source.includes("handoff?.source == 'pandora_intake'"), false);
  assert.equal(source.includes('keep this chat open while Pandora works'), true);
});

test('in-chat execution keeps one stable admission identity after mutation acceptance', () => {
  assert.match(
    source,
    /_keys\.create\(\s*['"]pandora-chat-project-change['"]\s*,?\s*\)/,
  );
  assert.equal(source.includes("idempotencyKey: '$executionKey:intent'"), true);
  assert.equal(source.includes("idempotencyKey: '$executionKey:build:$intentId'"), true);
  assert.equal(source.includes('var mutationAccepted = false;'), true);
  assert.equal(source.includes('mutationAccepted = true;'), true);
  assert.equal(source.includes('_outcomeUnknown = true;'), true);
  assert.equal(source.includes('will not retry it automatically'), true);
});

const workspace = fs.readFileSync(
  path.join(process.cwd(), 'apps/pandora-mobile/lib/features/simple/project_experience_v2.dart'),
  'utf8',
);

test('workspace can still consume an initial project change when opened explicitly elsewhere', () => {
  assert.equal(workspace.includes('final String? initialChange;'), true);
  assert.equal(workspace.includes('next.canChange'), true);
  assert.equal(workspace.includes('unawaited(_requestInitialChange(initialChange))'), true);
});

test('routed initial workspace changes retry safely with one stable admission key per workspace attempt', () => {
  assert.equal(workspace.includes('bool _initialChangeSubmitting = false;'), true);
  assert.equal(workspace.includes('String? _initialChangeIdempotencyKey;'), true);
  assert.equal(workspace.includes('idempotencyKey: _initialChangeIdempotencyKey'), true);
  assert.equal(workspace.includes('if (_error == null && !_changing) _initialChangeSubmitted = true;'), true);
  assert.equal(workspace.includes('idempotencyKey ??'), true);
  assert.equal(workspace.includes('idempotencyKey: changeIdempotencyKey'), true);
});
