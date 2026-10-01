import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import test from 'node:test';

import {
  InMemoryReplayClaimStore,
  WebhookVerificationError,
  verifySignedWebhook,
} from '../packages/pandora-connections-quality/src/webhook-defense.mjs';

const now = new Date('2026-10-01T12:00:00.000Z');
const timestamp = Math.floor(now.getTime() / 1000);
const secret = 'fixture-only-signing-secret';
const body = Buffer.from('{"event":"updated","id":"evt-1"}');

function signature(payload = body, at = timestamp) {
  return `sha256=${createHmac('sha256', secret)
    .update(Buffer.concat([Buffer.from(`${at}.`), payload]))
    .digest('hex')}`;
}

test('signed webhook verifies timestamp and returns only hashed evidence', async () => {
  const receipt = await verifySignedWebhook({
    rawBody: body,
    signature: signature(),
    timestamp,
    idempotencyKey: 'delivery-1',
    secret,
    claimStore: new InMemoryReplayClaimStore(() => now),
    now,
  });
  assert.equal(receipt.signatureVerified, true);
  assert.equal(receipt.timestampFresh, true);
  assert.match(receipt.payloadHash, /^[0-9a-f]{64}$/);
  assert.match(receipt.idempotencyHash, /^[0-9a-f]{64}$/);
  assert.doesNotMatch(JSON.stringify(receipt), /fixture-only|delivery-1|updated/);
});

test('duplicate signed webhook is rejected by the atomic replay claim', async () => {
  const store = new InMemoryReplayClaimStore(() => now);
  const request = {
    rawBody: body,
    signature: signature(),
    timestamp,
    idempotencyKey: 'delivery-1',
    secret,
    claimStore: store,
    now,
  };
  await verifySignedWebhook(request);
  await assert.rejects(
    verifySignedWebhook(request),
    (error) => error instanceof WebhookVerificationError && error.code === 'replay_detected',
  );
});

test('a duplicate delivery ID is rejected even when a newly signed body differs', async () => {
  const store = new InMemoryReplayClaimStore(() => now);
  await verifySignedWebhook({
    rawBody: body,
    signature: signature(),
    timestamp,
    idempotencyKey: 'delivery-stable',
    secret,
    claimStore: store,
    now,
  });
  const altered = Buffer.from('{"event":"updated","id":"evt-2"}');
  await assert.rejects(
    verifySignedWebhook({
      rawBody: altered,
      signature: signature(altered),
      timestamp,
      idempotencyKey: 'delivery-stable',
      secret,
      claimStore: store,
      now,
    }),
    (error) => error.code === 'replay_detected',
  );
});

test('stale and future timestamps are rejected before replay claim', async () => {
  for (const at of [timestamp - 301, timestamp + 301]) {
    await assert.rejects(
      verifySignedWebhook({
        rawBody: body,
        signature: signature(body, at),
        timestamp: at,
        idempotencyKey: `delivery-${at}`,
        secret,
        claimStore: new InMemoryReplayClaimStore(() => now),
        now,
      }),
      (error) => error.code === 'stale_timestamp',
    );
  }
});

test('missing, malformed, mismatched, and body-substitution signatures fail closed', async () => {
  const cases = [
    undefined,
    'sha256=bad',
    `sha256=${'0'.repeat(64)}`,
    signature(Buffer.from('{"event":"different"}')),
  ];
  for (const supplied of cases) {
    await assert.rejects(
      verifySignedWebhook({
        rawBody: body,
        signature: supplied,
        timestamp,
        idempotencyKey: `delivery-${cases.indexOf(supplied)}`,
        secret,
        claimStore: new InMemoryReplayClaimStore(() => now),
        now,
      }),
      (error) => ['invalid_signature', 'signature_mismatch'].includes(error.code),
    );
  }
});

test('verification errors never expose the secret or body', async () => {
  try {
    await verifySignedWebhook({
      rawBody: body,
      signature: `sha256=${'0'.repeat(64)}`,
      timestamp,
      idempotencyKey: 'delivery-redaction',
      secret,
      claimStore: new InMemoryReplayClaimStore(() => now),
      now,
    });
    assert.fail('expected signature mismatch');
  } catch (error) {
    assert.doesNotMatch(String(error), /fixture-only|updated|evt-1/);
  }
});
