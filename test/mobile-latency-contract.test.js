const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');

const root = join(__dirname, '..');
const workspace = readFileSync(
  join(root, 'apps', 'pandora-mobile', 'lib', 'features', 'simple', 'project_experience_v2.dart'),
  'utf8',
);
const creation = readFileSync(
  join(root, 'apps', 'pandora-mobile', 'lib', 'features', 'simple', 'project_create_experience.dart'),
  'utf8',
);

test('workspace startup avoids duplicate hydration and coalesces overlapping refreshes', () => {
  assert.match(
    workspace,
    /didChangeDependencies\(\)[\s\S]*?_initializeWorkspace\(\)[\s\S]*?Future<void> _initializeWorkspace\(\)[\s\S]*?_startProjection\(hydrateInitial: false\)[\s\S]*?await _refresh\(\)/,
  );
  assert.match(
    workspace,
    /Future<void> _refresh\(\)[\s\S]*?final active = _refreshTask;[\s\S]*?_refreshAgain = true;[\s\S]*?_runRefreshLoop\(\)/,
  );
  assert.match(
    workspace,
    /void _acceptProjection\([\s\S]*?bool hydrate = true[\s\S]*?if \(hydrate && shouldHydrate\) unawaited\(_refresh\(\)\)/,
  );
});

test('workspace starts independent authoritative reads before awaiting any of them', () => {
  const start = workspace.indexOf('Future<void> _refreshOnce() async {');
  const end = workspace.indexOf('Future<void> _openExactPreview()', start);
  assert.notEqual(start, -1);
  assert.notEqual(end, -1);
  const refresh = workspace.slice(start, end);
  const runtimeStart = refresh.indexOf('final snapshotFuture = experience.runtime(');
  const projectionStart = refresh.indexOf('final projectionFuture = experience.loadExperience(');
  const receiptStart = refresh.indexOf('final publishReceiptFuture = _readLatestPublishReceipt(experience);');
  const firstAwait = refresh.indexOf('final snapshot = await snapshotFuture;');
  assert.ok(runtimeStart >= 0 && projectionStart >= 0 && receiptStart >= 0);
  assert.ok(runtimeStart < firstAwait && projectionStart < firstAwait && receiptStart < firstAwait);
});

test('project understanding polling cannot stack and stops at terminal state', () => {
  assert.match(
    creation,
    /Future<void> _refresh\(\) async \{[\s\S]*?if \(_refreshing\) return;[\s\S]*?_refreshing = true;/,
  );
  assert.match(
    creation,
    /value\.state != OwnerProjectUnderstandingState\.waiting[\s\S]*?_timer\?\.cancel\(\)/,
  );
  assert.match(creation, /finally \{[\s\S]*?_refreshing = false;/);
});
