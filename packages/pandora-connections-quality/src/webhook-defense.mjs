import { createHash, createHmac, timingSafeEqual } from 'node:crypto';

const keyPattern = /^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$/;

function equalText(left, right) {
  const leftBuffer = Buffer.from(left, 'utf8');
  const rightBuffer = Buffer.from(right, 'utf8');
  return leftBuffer.length === rightBuffer.length && timingSafeEqual(leftBuffer, rightBuffer);
}

export class WebhookVerificationError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'WebhookVerificationError';
    this.code = code;
  }
}

export class InMemoryReplayClaimStore {
  constructor(now = () => new Date()) {
    this.now = now;
    this.claims = new Map();
  }

  async claim(keyHash, expiresAt) {
    const nowMs = this.now().getTime();
    for (const [key, expiry] of this.claims.entries()) {
      if (expiry <= nowMs) this.claims.delete(key);
    }
    if (this.claims.has(keyHash)) return false;
    this.claims.set(keyHash, Date.parse(expiresAt));
    return true;
  }
}

export async function verifySignedWebhook({
  rawBody,
  signature,
  timestamp,
  idempotencyKey,
  secret,
  claimStore,
  now = new Date(),
  maxSkewSeconds = 300,
  replayWindowSeconds = 24 * 60 * 60,
  maxBodyBytes = 256 * 1024,
}) {
  const body = Buffer.isBuffer(rawBody) ? rawBody : Buffer.from(rawBody ?? '');
  if (body.length === 0 || body.length > maxBodyBytes) {
    throw new WebhookVerificationError('invalid_body_size', 'Webhook body size is outside the allowed range');
  }
  if (typeof secret !== 'string' || !secret) {
    throw new WebhookVerificationError('secret_unavailable', 'Webhook signing material is unavailable');
  }
  if (typeof idempotencyKey !== 'string' || !keyPattern.test(idempotencyKey)) {
    throw new WebhookVerificationError('invalid_idempotency_key', 'Webhook idempotency key is invalid');
  }
  if (!Number.isInteger(timestamp)) {
    throw new WebhookVerificationError('invalid_timestamp', 'Webhook timestamp must be Unix seconds');
  }
  if (!Number.isInteger(maxSkewSeconds) || maxSkewSeconds < 1 || maxSkewSeconds > 3600) {
    throw new TypeError('maxSkewSeconds must be between 1 and 3600');
  }
  const nowDate = new Date(now);
  const skewSeconds = Math.abs(Math.floor(nowDate.getTime() / 1000) - timestamp);
  if (skewSeconds > maxSkewSeconds) {
    throw new WebhookVerificationError('stale_timestamp', 'Webhook timestamp is outside the allowed window');
  }
  const match = /^sha256=([0-9a-f]{64})$/i.exec(String(signature ?? '').trim());
  if (!match) {
    throw new WebhookVerificationError('invalid_signature', 'Webhook signature header is invalid');
  }
  const signedPayload = Buffer.concat([Buffer.from(`${timestamp}.`, 'utf8'), body]);
  const expected = createHmac('sha256', secret).update(signedPayload).digest('hex');
  if (!equalText(expected, match[1].toLowerCase())) {
    throw new WebhookVerificationError('signature_mismatch', 'Webhook signature mismatch');
  }
  if (!claimStore || typeof claimStore.claim !== 'function') {
    throw new TypeError('claimStore.claim is required');
  }
  const payloadHash = createHash('sha256').update(body).digest('hex');
  const idempotencyHash = createHash('sha256')
    .update(idempotencyKey)
    .digest('hex');
  // Claim the delivery identity itself. A repeated provider delivery ID must be
  // rejected even if the body differs; binding the claim to the payload would
  // let an altered replay bypass idempotency.
  const claimHash = idempotencyHash;
  const expiresAt = new Date(nowDate.getTime() + replayWindowSeconds * 1000).toISOString();
  if (!(await claimStore.claim(claimHash, expiresAt))) {
    throw new WebhookVerificationError('replay_detected', 'Duplicate webhook delivery rejected');
  }
  return Object.freeze({
    contractVersion: 'pandora-signed-webhook-v1',
    signatureVerified: true,
    timestampFresh: true,
    payloadHash,
    idempotencyHash,
    receivedAt: nowDate.toISOString(),
    expiresAt,
  });
}
