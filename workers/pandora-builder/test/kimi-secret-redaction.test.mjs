import assert from 'node:assert/strict';
import test from 'node:test';

import { createLogRecord, redactText } from '../src/logs/log-records.mjs';

const FAKE = ['sk', 'moonshot-test-only', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ123456'].join('-');

test('builder logs redact Moonshot/Kimi credential forms', () => {
  const input = [
    `MOONSHOT_API_KEY=${FAKE}`,
    `KIMI_API_KEY=${FAKE}`,
    `Authorization: Bearer ${FAKE}`,
    `api_key=${FAKE}`,
  ].join('\n');
  const redacted = redactText(input, [FAKE]);
  assert.ok(!redacted.includes(FAKE));
  const record = createLogRecord({
    stream: 'worker',
    text: input,
    executionId: 'test-execution',
    step: 'kimi-security',
    secrets: [FAKE],
  });
  assert.ok(!record.inline.includes(FAKE));
});
