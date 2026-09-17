import test from 'node:test';
import assert from 'node:assert/strict';

const standaloneSkShape = /(?:^|[^A-Za-z0-9])s[k]-[A-Za-z0-9_-]{20,}/;

test('RDP secret detector ignores ask-* UI identifiers', () => {
  const uiKey = 'ask-pandora-communication-status-key';
  assert.equal(standaloneSkShape.test(uiKey), false);
});

test('RDP secret detector still catches a standalone sk token shape', () => {
  const token = 's' + 'k-' + 'A'.repeat(24);
  assert.equal(standaloneSkShape.test(`'${token}'`), true);
});
