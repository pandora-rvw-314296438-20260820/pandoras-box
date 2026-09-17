import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const retention = await readFile(
  '.github/workflows/pandora-artifact-retention.yml',
  'utf8',
);
const mobile = await readFile(
  '.github/workflows/pandora-mobile-integration.yml',
  'utf8',
);

test('artifact retention is isolated from the read-only mobile gate', () => {
  assert.match(retention, /actions: write/);
  assert.match(retention, /contents: read/);
  assert.match(retention, /workflow_run:/);
  assert.match(retention, /schedule:/);
  assert.match(retention, /MAX_DELETIONS: '250'/);
  assert.doesNotMatch(retention, /actions\/checkout/);
});
test('cleanup deletes only expired artifacts or superseded Web candidates', () => {
  assert.match(retention, /if \[\[ "\$expired" == 'true' \]\]/);
  assert.match(retention, /pandora-mobile-web-validation/);
  assert.match(retention, /"\$head_sha" != "\$main_sha"/);
  assert.match(retention, /gh api -X DELETE/);
  assert.doesNotMatch(retention, /pandora-mobile-android-validation/);
  assert.doesNotMatch(retention, /canonical-release-source/);
});

test('mobile retention preserves main Android authority but shortens transient candidates', () => {
  assert.match(
    mobile,
    /name: pandora-mobile-web-validation[\s\S]*?retention-days: 1/,
  );
  assert.match(
    mobile,
    /name: \$\{\{ env\.ANDROID_ARTIFACT_NAME \}\}[\s\S]*?retention-days: \$\{\{ github\.event_name == 'push' && 14 \|\| 1 \}\}/,
  );
  assert.match(mobile, /id: upload_android_validation/);
  assert.match(mobile, /steps\.upload_android_validation\.outputs\.artifact-id/);
});
