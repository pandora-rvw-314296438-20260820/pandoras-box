'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const analytics = readFileSync(
  path.join(root, 'apps/pandora-mobile/lib/core/analytics/owner_analytics.dart'),
  'utf8',
);
const repository = readFileSync(
  path.join(root, 'apps/pandora-mobile/lib/core/data/project_experience_repository.dart'),
  'utf8',
);

test('visible creation funnel exposes bounded second-change conversion', () => {
  assert.match(analytics, /secondChange\('second_change'\)/);
  assert.match(repository, /submissionCount == 2/);
  assert.match(repository, /OwnerAnalyticsEvent\.secondChange/);
  assert.match(repository, /count: submissionCount/);
  assert.match(repository, /status: 'submitted'/);
  assert.match(repository, /_successfulChangeSubmissions\.clear\(\)/);
});

test('drop-off reasons are a closed bounded vocabulary', () => {
  assert.match(analytics, /funnelDropOff\('funnel_dropoff'\)/);
  assert.match(repository, /enum _OwnerFunnelDropOffReason/);
  for (const reason of [
    'change_submit_rejected',
    'change_submit_failed',
    'build_request_rejected',
    'build_request_failed',
    'preview_request_rejected',
    'preview_request_failed',
  ]) {
    assert.ok(repository.includes(`'${reason}'`));
  }
  assert.match(repository, /status: reason\.wireName/);
});

test('funnel analytics never send raw change text or owner request content', () => {
  const secondChangeStart = repository.indexOf('OwnerAnalyticsEvent.secondChange');
  const secondChangeEnd = repository.indexOf('return intentId;', secondChangeStart);
  assert.ok(secondChangeStart >= 0 && secondChangeEnd > secondChangeStart);
  const captureBlock = repository.slice(secondChangeStart, secondChangeEnd);
  assert.doesNotMatch(captureBlock, /changeText:|intentText:|actionRequest|raw[_A-Za-z]/);

  const dropOffStart = repository.indexOf('void _captureDropOff');
  const dropOffEnd = repository.indexOf('@override', dropOffStart);
  assert.ok(dropOffStart >= 0 && dropOffEnd > dropOffStart);
  const dropOffBlock = repository.slice(dropOffStart, dropOffEnd);
  assert.doesNotMatch(dropOffBlock, /changeText|intentText|actionRequest|requestBody/);

  assert.doesNotMatch(
    analytics,
    /raw_prompt|raw_source|provider_response|generated_source|credential_value/i,
  );
});

test('funnel residual instrumentation covers build and preview failure points', () => {
  for (const token of [
    '_OwnerFunnelDropOffReason.changeSubmitRejected',
    '_OwnerFunnelDropOffReason.changeSubmitFailed',
    '_OwnerFunnelDropOffReason.buildRequestRejected',
    '_OwnerFunnelDropOffReason.buildRequestFailed',
    '_OwnerFunnelDropOffReason.previewRequestRejected',
    '_OwnerFunnelDropOffReason.previewRequestFailed',
  ]) {
    assert.ok(repository.includes(token));
  }
});
