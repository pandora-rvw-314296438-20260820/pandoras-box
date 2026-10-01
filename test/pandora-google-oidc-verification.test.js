const assert = require('node:assert/strict');
const { createHash, generateKeyPairSync, sign } = require('node:crypto');
const { join } = require('node:path');
const { pathToFileURL } = require('node:url');
const test = require('node:test');

const modulePath = pathToFileURL(join(
  __dirname,
  '../supabase/functions/pandora-google-workspace-oauth/google_oidc_verification.mjs',
)).href;

const NOW_MS = Date.UTC(2026, 9, 1, 14, 0, 0);
const CLIENT_ID = 'pandora-google-client.apps.googleusercontent.com';
const NONCE = 'nonce-bound-to-one-time-state-0123456789';
const NONCE_HASH = createHash('sha256').update(NONCE).digest('hex');
const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const publicJwk = {
  ...publicKey.export({ format: 'jwk' }),
  kid: 'google-test-key-1',
  alg: 'RS256',
  use: 'sig',
};

function encode(value) {
  return Buffer.from(JSON.stringify(value)).toString('base64url');
}

function makeToken(overrides = {}) {
  const header = encode({ alg: 'RS256', typ: 'JWT', kid: publicJwk.kid });
  const payload = encode({
    iss: 'https://accounts.google.com',
    aud: CLIENT_ID,
    azp: CLIENT_ID,
    sub: '109876543210987654321',
    email: 'owner@example.com',
    email_verified: true,
    name: 'Owner <Admin>',
    hd: 'example.com',
    nonce: NONCE,
    iat: Math.floor(NOW_MS / 1000) - 30,
    exp: Math.floor(NOW_MS / 1000) + 3600,
    ...overrides,
  });
  const signature = sign('RSA-SHA256', Buffer.from(`${header}.${payload}`), privateKey).toString('base64url');
  return `${header}.${payload}.${signature}`;
}

function jwksFetch(calls) {
  return async (url, options) => {
    calls.push({ url, options });
    return {
      ok: true,
      async json() { return { keys: [publicJwk] }; },
    };
  };
}

test('Google ID token verification uses the fixed Google JWKS and validates nonce-bound identity', async () => {
  const verifier = await import(modulePath);
  const calls = [];
  const identity = await verifier.verifyGoogleIdToken({
    idToken: makeToken(),
    clientId: CLIENT_ID,
    expectedNonceHash: NONCE_HASH,
    fetcher: jwksFetch(calls),
    now: () => NOW_MS,
  });

  assert.equal(identity.subject, '109876543210987654321');
  assert.equal(identity.email, 'owner@example.com');
  assert.equal(identity.nonce, NONCE);
  assert.deepEqual(calls.map(({ url }) => url), ['https://www.googleapis.com/oauth2/v3/certs']);
  assert.equal(calls[0].options.redirect, 'error');
});

test('Google ID token verification fails closed for signature and trusted-claim violations', async (t) => {
  const verifier = await import(modulePath);
  const cases = [
    ['issuer', { iss: 'https://attacker.example' }, /issuer_invalid/],
    ['audience', { aud: 'other-client', azp: 'other-client' }, /audience_invalid/],
    ['expiry', { exp: Math.floor(NOW_MS / 1000) }, /expired/],
    ['future issue time', { iat: Math.floor(NOW_MS / 1000) + 120 }, /issued_at_invalid/],
    ['unverified email', { email_verified: false }, /email_unverified/],
  ];
  for (const [name, claims, pattern] of cases) {
    await t.test(name, async () => {
      await assert.rejects(
        verifier.verifyGoogleIdToken({
          idToken: makeToken(claims),
          clientId: CLIENT_ID,
          expectedNonceHash: NONCE_HASH,
          fetcher: jwksFetch([]),
          now: () => NOW_MS,
        }),
        pattern,
      );
    });
  }

  const valid = makeToken();
  const parts = valid.split('.');
  parts[2] = `${parts[2][0] === 'A' ? 'B' : 'A'}${parts[2].slice(1)}`;
  await assert.rejects(
    verifier.verifyGoogleIdToken({
      idToken: parts.join('.'),
      clientId: CLIENT_ID,
      expectedNonceHash: NONCE_HASH,
      fetcher: jwksFetch([]),
      now: () => NOW_MS,
    }),
    /signature_invalid/,
  );
});

test('nonce hashes are state-bound and scope normalization permits only exact read-first access', async () => {
  const verifier = await import(modulePath);
  await assert.rejects(
    verifier.verifyGoogleIdToken({
      idToken: makeToken(),
      clientId: CLIENT_ID,
      expectedNonceHash: '0'.repeat(64),
      fetcher: jwksFetch([]),
      now: () => NOW_MS,
    }),
    /nonce_mismatch/,
  );

  const canonical = verifier.normalizeGoogleScopes([
    'openid',
    'https://www.googleapis.com/auth/userinfo.email',
    'https://www.googleapis.com/auth/userinfo.profile',
    'https://www.googleapis.com/auth/drive.metadata.readonly',
    'https://www.googleapis.com/auth/spreadsheets.readonly',
  ]);
  assert.equal(verifier.hasExactGoogleReadScopes(canonical), true);
  assert.equal(verifier.hasExactGoogleReadScopes([
    ...canonical,
    'https://www.googleapis.com/auth/drive',
  ]), false);
  assert.equal(verifier.hasExactGoogleReadScopes(canonical.filter((scope) => scope !== 'profile')), false);
});
