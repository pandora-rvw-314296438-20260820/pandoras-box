const test = require('node:test');
const assert = require("node:assert/strict");
const fs = require('node:fs');
const path = require('node:path');

const source = ['ask_pandora_screen.dart', 'chat/pandora_chat_action_adapters.dart']
  .map(file => fs.readFileSync(path.join(process.cwd(), 'apps/pandora-mobile/lib/features/simple', file), 'utf8')).join('\n');

test('Ask Pandora fallback stays universal when intelligence is unavailable', () => {
  assert.equal(source.includes("import 'project_create_experience.dart';"), false);
  assert.equal(source.includes('idempotencyKey: token.attemptId'), true);
  assert.equal(source.includes('final receipt = await dependencies.repository.ask('), true);
  assert.equal(source.includes('initialIntent: objective'), false);
});

test('capability handoffs remain receipts and are never submitted as a second chat request', () => {
  assert.equal(source.includes('message: handoff.request'), false);
  assert.equal(source.includes("_keys.create('intelligence-handoff')"), false);
  assert.equal(source.includes('intelligence.executeChatTurn(dispatch)'), true);
  assert.equal(source.includes('intelligence.startChatExecution('), false);
  assert.equal(source.includes('initialIntent: handoff.request'), false);
});

test('Ask Pandora never presents the static prototype as a real build result', () => {
  assert.equal(source.includes("import 'build_preview_flow.dart';"), false);
  assert.equal(source.includes('BuildProgressScreen('), false);
});

test('explicit selected-project changes execute through the real builder without leaving chat', () => {
  assert.equal(source.includes('message: handoff.request'), false);
  assert.equal(source.includes("handoff?.source == 'project_workspace_change'"), true);
  assert.equal(source.includes('experience.loadExperience(projectId)'), true);
  assert.equal(source.includes("projection.state.name == 'build'"), true);
  assert.equal(source.includes("idempotencyKey: '${token.attemptId}:initial-build'"), true);
  assert.equal(source.includes('The build request was accepted.'), true);
  assert.equal(source.includes('projection.activeBuildJobId != null'), true);
  assert.equal(source.includes('experience.submitChange('), true);
  assert.equal(source.includes('experience.understanding('), true);
  assert.equal(source.includes('experience.requestBuild('), true);
  assert.equal(source.includes('ProjectWorkspaceV2Screen('), false);
  assert.equal(source.includes('initialChange: handoff!.request'), false);
  assert.equal(source.includes("handoff?.source == 'projectos_intake'"), false);
  assert.equal(source.includes('You can follow it in Activity.'), true);
});

test('in-chat execution keeps one stable admission identity after mutation acceptance', () => {
  assert.match(source, /final token = dispatch\.token/);
  assert.equal(source.includes("idempotencyKey: '${token.attemptId}:intent'"), true);
  assert.equal(source.includes("idempotencyKey: '${token.attemptId}:build:$intentId'"), true);
  assert.equal(source.includes('var mutationAccepted = false;'), true);
  assert.equal(source.includes('mutationAccepted = true;'), true);
  assert.equal(source.includes('outcomeUnknown: mutationAccepted'), true);
  assert.equal(source.includes('recoverable: !mutationAccepted'), true);
  assert.match(source, /if \(!_current\(token\)\)/);
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
