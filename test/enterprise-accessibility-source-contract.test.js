const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const read = (relativePath) =>
  fs.readFileSync(path.join(root, relativePath), 'utf8');

const commandStack = read(
  'apps/pandora-mobile/lib/features/enterprise/enterprise_command_stack.dart',
);
const activityView = read(
  'apps/pandora-mobile/lib/core/activity/pandora_activity_timeline_view.dart',
);
const v2 = read('apps/pandora-mobile/lib/features/simple/pandora_v2_ui.dart');
const code = read(
  'apps/pandora-mobile/lib/features/enterprise/enterprise_code_screen.dart',
);
const securityWorkflow = read('.github/workflows/pandora-security-regression.yml');

test('retired ProjectOS is not the active security workflow identity', () => {
  assert.equal(
    fs.existsSync(path.join(root, '.github/workflows/projectos-security.yml')),
    false,
  );
  assert.match(securityWorkflow, /^name: Pandora security regression/m);
  assert.doesNotMatch(securityWorkflow, /ProjectOS/i);
});

test('Enterprise command surface uses deterministic traversal and a truthful compact result receipt', () => {
  assert.match(commandStack, /FocusTraversalGroup/);
  assert.match(commandStack, /WidgetOrderTraversalPolicy/);
  assert.match(commandStack, /enterprise-view-result/);
  assert.match(commandStack, /View result/);
  assert.match(commandStack, /PandoraActivityTimelineView/);
  assert.doesNotMatch(commandStack, /\bUndo\b/);
});

test('Enterprise motion respects reduced-motion preference', () => {
  assert.match(activityView, /MediaQuery\.disableAnimationsOf\(context\)/);
  assert.match(v2, /MediaQuery\.disableAnimationsOf\(context\)/);
  assert.match(v2, /Duration\.zero/);
});

test('Code surface announces asynchronous provider state and errors', () => {
  assert.match(code, /Semantics\(/);
  assert.match(code, /liveRegion:\s*true/);
  assert.match(code, /Repository operation in progress/);
  assert.match(code, /Deployment provider readback/);
  assert.match(code, /errorText:\s*repositoryInputError/);
});

test('essential Enterprise control boundaries avoid the faint line token', () => {
  assert.match(
    commandStack,
    /border:\s*Border\.all\(color:\s*PandoraV2Colors\.muted\)/,
  );
  assert.match(
    v2,
    /border:\s*Border\.all\(color:\s*PandoraV2Colors\.muted\)/,
  );
});
