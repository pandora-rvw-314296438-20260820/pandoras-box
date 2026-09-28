'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const shell = fs.readFileSync('apps/pandora-mobile/lib/app/eurofish_enterprise_shell.dart','utf8');
const workflow = fs.readFileSync('.github/workflows/eurofish-pandora-enterprise-android.yml','utf8');

test('Euro-Fish chat history is workspace scoped', () => {
  assert.match(shell,/recentThreadsForWorkspace\(\s*_workspaceKey,\s*limit:\s*10,/s);
  assert.doesNotMatch(shell,/intelligence\.recentThreads\(\)/);
  assert.match(shell,/1064-euro-fish-traders/);
});

test('Euro-Fish APK publication is explicitly validation-only', () => {
  for (const required of [
    "ARTIFACT_CLASS: 'validation-candidate'",
    "PRODUCTION_RELEASE: 'false'",
    "DISTRIBUTION_SCOPE: 'github-actions-validation-only'",
    'artifact_class=$ARTIFACT_CLASS',
    'production_release=$PRODUCTION_RELEASE',
    'distribution_scope=$DISTRIBUTION_SCOPE',
    'production_signing_verified=false',
    'install_authority=none',
    'physical_device_verified=false',
    'Upload validation-only Euro-Fish APK and evidence',
    "if: ${{ github.event_name != 'pull_request' }}",
    'retention-days: 1',
    'EUROFISH_PANDORA_ANDROID_VALIDATION_RECEIPT',
  ]) assert.ok(workflow.includes(required), required);
  assert.doesNotMatch(workflow,/name:\s*eurofish-pandora-enterprise-\$\{\{ env\.SOURCE_SHA \}\}/);
});
