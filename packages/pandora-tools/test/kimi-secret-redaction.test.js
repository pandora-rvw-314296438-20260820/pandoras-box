'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');

const { REDACTED, redactDeep, redactString } = require('../src/redaction.js');

const FAKE = ['sk', 'moonshot-test-only', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ123456'].join('-');

test('redacts Moonshot/Kimi secret-bearing object keys', () => {
  const out = redactDeep({
    moonshot_api_key: FAKE,
    kimi_api_key: FAKE,
    safe: 'provider=moonshot',
  });
  assert.equal(out.moonshot_api_key, REDACTED);
  assert.equal(out.kimi_api_key, REDACTED);
  assert.equal(out.safe, 'provider=moonshot');
});

test('redacts Moonshot/Kimi env assignments, bearer values, sk tokens, and query credentials', () => {
  const samples = [
    `MOONSHOT_API_KEY=${FAKE}`,
    `KIMI_API_KEY=${FAKE}`,
    `Authorization: Bearer ${FAKE}`,
    FAKE,
    `https://example.invalid/callback?api_key=${FAKE}&mode=test`,
  ];
  for (const sample of samples) {
    const out = redactString(sample);
    assert.ok(!out.includes(FAKE), `secret leaked from ${sample.slice(0, 24)}`);
  }
});

test('canary redaction remains exact without destroying unrelated Moonshot evidence', () => {
  const out = redactDeep(
    { provider: 'moonshot', model: 'kimi-k3', detail: `canary=${FAKE}` },
    { canaries: [FAKE] },
  );
  assert.equal(out.provider, 'moonshot');
  assert.equal(out.model, 'kimi-k3');
  assert.ok(!out.detail.includes(FAKE));
});
