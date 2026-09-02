const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(
  path.join(__dirname, '..', 'apps', 'pandora-mobile', 'lib', 'core', 'analytics', 'owner_analytics.dart'),
  'utf8',
);

const requiredEvents = [
  'intent_sent',
  'proposal_shown',
  'build_clicked',
  'build_admitted',
  'build_admission_failed',
  'first_code',
  'file_complete',
  'preview_ready',
  'build_stalled',
  'repair_started',
  'repair_completed',
  'verification_failed',
  'second_change_submitted',
  'funnel_drop_off',
  'stream_reconnected',
  'history_gap',
  'publish_started',
  'publish_verified',
  'publish_failed',
  'source_paywall_viewed',
  'source_access_granted',
  'source_exported',
];

test('visible creation analytics vocabulary is explicit and complete', () => {
  for (const event of requiredEvents) {
    assert.match(source, new RegExp(`['\"]${event}['\"]`), `missing ${event}`);
  }
});

test('analytics properties remain typed and bounded instead of accepting arbitrary payloads', () => {
  for (const field of [
    'projectKey',
    'resultClass',
    'errorCode',
    'proofStage',
    'buildKey',
    'versionKey',
    'statusClass',
    'capability',
    'sequence',
    'itemCount',
    'attempt',
    'historyGap',
    'duration',
  ]) {
    assert.match(source, new RegExp(`\\b${field}\\b`), `missing typed field ${field}`);
  }
  assert.doesNotMatch(source, /Map<String,\s*Object\?>\?\s*(properties|payload|metadata)/);
  assert.doesNotMatch(source, /String\?\s*(prompt|intentText|sourceContent|stdout|stderr|credential|providerResponse)/);
});

test('bounded event envelope exposes only identifiers, enums, counts and durations', () => {
  for (const wireKey of [
    'project_key',
    'result_class',
    'error_code',
    'proof_stage',
    'build_key',
    'version_key',
    'status_class',
    'capability',
    'sequence',
    'item_count',
    'attempt',
    'history_gap',
    'duration_ms',
  ]) {
    assert.match(source, new RegExp(`['\"]${wireKey}['\"]`), `missing ${wireKey}`);
  }
  assert.match(source, /_bounded\(buildKey, 160\)/);
  assert.match(source, /_bounded\(versionKey, 160\)/);
  assert.match(source, /sequence != null && sequence >= 0/);
  assert.match(source, /itemCount != null && itemCount >= 0/);
});
