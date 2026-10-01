import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import test from 'node:test';

import healthModule from '../apps/meta-business-mcp/src/webhooks/health-store.js';
import processorModule from '../apps/meta-business-mcp/src/webhooks/processor.js';
import signatureModule from '../apps/meta-business-mcp/src/webhooks/signature.js';
import resolverModule from '../apps/meta-business-mcp/src/secrets/resolver.js';

const { InMemoryMetaWebhookHealthStore } = healthModule;
const { InMemoryMetaWebhookClaimStore, MetaWebhookProcessor } = processorModule;
const { MetaWebhookSignatureVerifier } = signatureModule;
const { InMemorySecretResolver } = resolverModule;

const now = new Date('2026-10-01T12:00:00.000Z');
const appSecret = 'fixture-meta-app-secret';
const appSecretRef = 'vault-ref-meta-app-secret';
const verifyTokenRef = 'vault-ref-meta-verify-token';
const body = Buffer.from(JSON.stringify({
  object: 'page',
  entry: [{ id: 'page-1', changes: [{ field: 'feed' }] }],
}));

function fixture() {
  const resolver = new InMemorySecretResolver({
    [appSecretRef]: appSecret,
    [verifyTokenRef]: 'fixture-verify-token',
  });
  const signatureVerifier = new MetaWebhookSignatureVerifier({
    appSecretRef,
    verifyTokenSecretRef: verifyTokenRef,
    secretResolver: resolver,
  });
  const healthStore = new InMemoryMetaWebhookHealthStore();
  const processor = new MetaWebhookProcessor({
    signatureVerifier,
    claimStore: new InMemoryMetaWebhookClaimStore(() => now),
    healthStore,
    allowedPageIds: ['page-1'],
    now: () => now,
  });
  const signature = `sha256=${createHmac('sha256', appSecret).update(body).digest('hex')}`;
  return { healthStore, processor, signature };
}

test('Meta webhook accepts a valid HMAC once and deduplicates replay', async () => {
  const f = fixture();
  const first = await f.processor.process(body, f.signature);
  const replay = await f.processor.process(body, f.signature);
  assert.equal(first.status, 'accepted');
  assert.equal(replay.status, 'duplicate');
  assert.equal(replay.deliveryId, first.deliveryId);
  const health = await f.healthStore.getWebhookHealth('page-1');
  assert.equal(health.status, 'healthy');
  assert.equal(health.failedDeliveries, 0);
});

test('Meta webhook rejects missing, malformed, mismatched, and substituted signatures', async () => {
  const f = fixture();
  const cases = [
    undefined,
    'sha256=bad',
    `sha256=${'0'.repeat(64)}`,
    `sha256=${createHmac('sha256', appSecret).update('different').digest('hex')}`,
  ];
  for (const supplied of cases) {
    await assert.rejects(f.processor.process(body, supplied));
  }
  try {
    await f.processor.process(body, `sha256=${'0'.repeat(64)}`);
    assert.fail('expected signature mismatch');
  } catch (error) {
    assert.doesNotMatch(String(error), /fixture-meta-app-secret|fixture-verify-token/);
  }
});
