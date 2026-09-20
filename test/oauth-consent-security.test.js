const assert = require('node:assert/strict');
const { readFile } = require('node:fs/promises');
const test = require('node:test');
const vm = require('node:vm');

let source;
let html;

test.before(async () => {
  [source, html] = await Promise.all([
    readFile('public/oauth/consent.browser.js.txt', 'utf8'),
    readFile('public/oauth/consent.html', 'utf8'),
  ]);
});

function createConsentHarness({
  authorizationId = 'authorization-test',
  callback = false,
  verifierRecord,
  accessToken = 'aal1-authenticated-access-token',
} = {}) {
  const listeners = new Map();
  const calls = [];
  const assignments = [];
  const element = (name) => ({
    name,
    hidden: true,
    disabled: false,
    textContent: '',
    classList: { toggle() {} },
    addEventListener(type, callbackFn) { listeners.set(`${name}:${type}`, callbackFn); },
    querySelector() { return null; },
  });
  const submitButton = element('submit');
  const elements = {
    '#status': element('status'),
    '#login': element('login'),
    '#github': element('github'),
    '#consent': element('consent'),
    '#client-copy': element('client-copy'),
    '#requested-scopes': element('requested-scopes'),
    '#approve': element('approve'),
    '#deny': element('deny'),
  };
  elements['#login'].querySelector = (selector) => (
    selector === 'button[type="submit"]' ? submitButton : null
  );

  const storage = new Map();
  if (verifierRecord) {
    storage.set('pandoras-box-consent-github-verifier', JSON.stringify(verifierRecord));
  }
  const sessionStorage = {
    getItem(key) { return storage.get(key) || null; },
    setItem(key, value) { storage.set(key, String(value)); },
    removeItem(key) { storage.delete(key); },
  };

  let cookie = '';
  const documentObject = {
    title: 'Consent',
    querySelector(selector) { return elements[selector]; },
  };
  Object.defineProperty(documentObject, 'cookie', {
    get() { return cookie; },
    set(value) {
      calls.push(['cookie', value]);
      cookie = /Max-Age=0/i.test(value) ? '' : String(value).split(';', 1)[0];
    },
  });

  let activeAccessToken = accessToken;
  const auth = {
    async signInWithPassword(input) {
      calls.push(['password', input]);
      return { error: null };
    },
    async getSession() {
      calls.push(['session']);
      return { data: { session: { access_token: activeAccessToken } }, error: null };
    },
    async setSession(tokens) {
      calls.push(['setSession', tokens]);
      activeAccessToken = tokens.access_token;
      return { data: { session: { access_token: activeAccessToken } }, error: null };
    },
    oauth: {
      async getAuthorizationDetails(id) {
        calls.push(['details', id]);
        return {
          data: {
            authorization_id: id,
            client: { name: 'Claude' },
            redirect_uri: 'https://claude.ai/api/mcp/auth_callback',
            scope: 'pandora:read pandora:approve',
          },
          error: null,
        };
      },
      async approveAuthorization(id) {
        calls.push(['approve', id]);
        return {
          data: { redirect_url: 'https://provider.example/approved-exact' },
          error: null,
        };
      },
      async denyAuthorization(id) {
        calls.push(['deny', id]);
        return {
          data: { redirect_url: 'https://provider.example/denied-exact' },
          error: null,
        };
      },
    },
  };
  Object.defineProperty(auth, 'mfa', {
    get() { throw new Error('OAuth consent accessed the forbidden MFA API'); },
  });

  const supabaseUrl = 'https://example.supabase.co';
  const fetchMock = async (url, options = {}) => {
    calls.push(['fetch', url, options]);
    if (url === '/api/operator/auth/config') {
      return {
        ok: true,
        async json() {
          return {
            supabaseUrl,
            supabasePublishableKey: 'sb_publishable_example01234567890',
          };
        },
      };
    }
    if (url === `${supabaseUrl}/auth/v1/token?grant_type=pkce`) {
      return {
        ok: true,
        async json() {
          return {
            access_token: 'github-aal1-access-token',
            refresh_token: 'github-refresh-token',
          };
        },
      };
    }
    if (url === '/api/operator/session') {
      return { ok: true, async json() { return { ok: true }; } };
    }
    throw new Error(`Unexpected fetch: ${url}`);
  };

  const query = new URLSearchParams({ authorization_id: authorizationId });
  if (callback) {
    query.set('oauth_callback', 'github-consent');
    query.set('code', 'github-provider-code');
  }
  const location = {
    href: `https://mcpmaster.vercel.app/oauth/consent?${query}`,
    origin: 'https://mcpmaster.vercel.app',
    search: `?${query}`,
    assign(value) { assignments.push(value); },
  };
  const script = source.replace(
    /^import \{ createClient \} from [^;]+;\s*/,
    'const createClient = globalThis.__createClient;\n',
  );
  const context = {
    __createClient() { calls.push(['createClient']); return { auth }; },
    window: {
      location,
      history: { replaceState(...args) { calls.push(['replaceState', ...args]); } },
    },
    document: documentObject,
    sessionStorage,
    fetch: fetchMock,
    FormData: class {
      get(name) { return name === 'email' ? 'owner@example.com' : 'password'; }
    },
    URL,
    URLSearchParams,
    Uint8Array,
    TextEncoder,
    crypto: globalThis.crypto,
    btoa(value) { return Buffer.from(value, 'binary').toString('base64'); },
    console,
    setTimeout,
    clearTimeout,
  };
  vm.runInNewContext(script, context, { filename: 'consent.browser.js' });
  return { auth, calls, elements, listeners, assignments };
}

async function waitFor(predicate, description) {
  for (let attempt = 0; attempt < 50; attempt += 1) {
    if (predicate()) return;
    await new Promise((resolve) => setImmediate(resolve));
  }
  assert.fail(`Timed out waiting for ${description}`);
}

test('OAuth consent has no TOTP enrollment, challenge, verification, or AAL gate', () => {
  assert.doesNotMatch(source, /\.auth\.mfa|totp|challengeAndVerify|assuranceLevel|aal1|aal2/i);
  assert.doesNotMatch(html, /authenticator code|six-digit|totp|mfa|aal1|aal2/i);
  assert.match(source, /await showConsent\(\)/);
});

test('authenticated AAL1 password session reaches consent without touching an MFA API', async () => {
  const listeners = new Map();
  const element = (name) => ({
    name,
    hidden: true,
    disabled: false,
    textContent: '',
    classList: { toggle() {} },
    addEventListener(type, callback) { listeners.set(`${name}:${type}`, callback); },
    querySelector(selector) {
      if (selector === 'button[type="submit"]') return submitButton;
      return null;
    },
  });
  const submitButton = element('submit');
  const elements = {
    '#status': element('status'),
    '#login': element('login'),
    '#github': element('github'),
    '#consent': element('consent'),
    '#client-copy': element('client-copy'),
    '#requested-scopes': element('requested-scopes'),
    '#approve': element('approve'),
    '#deny': element('deny'),
  };
  const calls = [];
  const auth = {
    async signInWithPassword(input) { calls.push(['password', input]); return { error: null }; },
    async getSession() {
      return { data: { session: { access_token: 'aal1-authenticated-access-token' } }, error: null };
    },
    async setSession() { throw new Error('GitHub callback is not active'); },
    oauth: {
      async getAuthorizationDetails(id) {
        calls.push(['details', id]);
        return {
          data: {
            authorization_id: id,
            client: { name: 'Claude' },
            redirect_uri: 'https://claude.ai/api/mcp/auth_callback',
            scope: 'pandora:read pandora:approve',
          },
          error: null,
        };
      },
      async approveAuthorization() { return { data: { redirect_url: 'https://claude.ai/callback' }, error: null }; },
      async denyAuthorization() { return { data: { redirect_url: 'https://claude.ai/callback' }, error: null }; },
    },
  };
  Object.defineProperty(auth, 'mfa', {
    get() { throw new Error('OAuth consent accessed the forbidden MFA API'); },
  });

  const fetchMock = async (url) => {
    if (url === '/api/operator/auth/config') {
      return {
        ok: true,
        async json() {
          return {
            supabaseUrl: 'https://example.supabase.co',
            supabasePublishableKey: 'sb_publishable_example01234567890',
          };
        },
      };
    }
    if (url === '/api/operator/session') return { ok: true, async json() { return { ok: true }; } };
    throw new Error(`Unexpected fetch: ${url}`);
  };

  const script = source.replace(
    /^import \{ createClient \} from [^;]+;\s*/,
    'const createClient = globalThis.__createClient;\n',
  );
  const location = {
    href: 'https://mcpmaster.vercel.app/oauth/consent?authorization_id=authorization-test',
    origin: 'https://mcpmaster.vercel.app',
    search: '?authorization_id=authorization-test',
    assign() {},
  };
  const context = {
    __createClient() { calls.push(['createClient']); return { auth }; },
    window: { location, history: { replaceState() {} } },
    document: {
      title: 'Consent',
      cookie: '',
      querySelector(selector) { return elements[selector]; },
    },
    fetch: fetchMock,
    FormData: class {
      get(name) { return name === 'email' ? 'owner@example.com' : 'password'; }
    },
    URL,
    URLSearchParams,
    Uint8Array,
    TextEncoder,
    crypto: globalThis.crypto,
    btoa(value) { return Buffer.from(value, 'binary').toString('base64'); },
    console,
    setTimeout,
    clearTimeout,
  };
  vm.runInNewContext(script, context, { filename: 'consent.browser.js' });
  await new Promise((resolve) => setImmediate(resolve));

  const submit = listeners.get('login:submit');
  assert.equal(typeof submit, 'function');
  await submit({ preventDefault() {}, currentTarget: elements['#login'] });

  assert.equal(elements['#consent'].hidden, false);
  assert.deepEqual(calls.map(([name]) => name), ['createClient', 'password', 'details']);
});

test('fresh authorization-bound GitHub PKCE callback reaches consent at AAL1 without MFA', async () => {
  const authorizationId = 'authorization-github-aal1';
  const verifier = 'v'.repeat(64);
  const harness = createConsentHarness({
    authorizationId,
    callback: true,
    verifierRecord: {
      verifier,
      authorizationId,
      createdAt: Date.now(),
    },
  });

  await waitFor(() => harness.elements['#consent'].hidden === false, 'GitHub consent');

  const tokenExchange = harness.calls.find(
    ([name, url]) => name === 'fetch' && String(url).includes('grant_type=pkce'),
  );
  assert.ok(tokenExchange);
  assert.equal(tokenExchange[2].redirect, 'error');
  assert.deepEqual(JSON.parse(tokenExchange[2].body), {
    auth_code: 'github-provider-code',
    code_verifier: verifier,
  });
  const establishedSession = harness.calls.find(([name]) => name === 'setSession')?.[1];
  assert.equal(establishedSession?.access_token, 'github-aal1-access-token');
  assert.equal(establishedSession?.refresh_token, 'github-refresh-token');
  assert.deepEqual(
    harness.calls.filter(([name]) => name === 'details').map(([, id]) => id),
    [authorizationId],
  );
});

test('mismatched or expired GitHub verifier state fails before token exchange', async (t) => {
  const authorizationId = 'authorization-state-boundary';
  const cases = [
    {
      name: 'mismatched authorization',
      record: {
        verifier: 'm'.repeat(64),
        authorizationId: 'different-authorization',
        createdAt: Date.now(),
      },
    },
    {
      name: 'expired verifier',
      record: {
        verifier: 'e'.repeat(64),
        authorizationId,
        createdAt: Date.now() - (11 * 60 * 1000),
      },
    },
  ];

  for (const scenario of cases) {
    await t.test(scenario.name, async () => {
      const harness = createConsentHarness({
        authorizationId,
        callback: true,
        verifierRecord: scenario.record,
      });
      await waitFor(
        () => /could not be resumed/i.test(harness.elements['#status'].textContent),
        `${scenario.name} rejection`,
      );
      assert.equal(
        harness.calls.some(([name, url]) => name === 'fetch' && String(url).includes('grant_type=pkce')),
        false,
      );
      assert.equal(harness.calls.some(([name]) => name === 'setSession'), false);
      assert.equal(harness.calls.some(([name]) => name === 'details'), false);
      assert.equal(harness.elements['#login'].hidden, false);
    });
  }
});

test('approve and deny bind the exact authorization ID and use provider redirects', async (t) => {
  for (const decision of ['approve', 'deny']) {
    await t.test(decision, async () => {
      const authorizationId = `authorization-${decision}-exact`;
      const harness = createConsentHarness({ authorizationId });
      await waitFor(() => harness.elements['#login'].hidden === false, `${decision} login`);

      await harness.listeners.get('login:submit')({ preventDefault() {} });
      assert.equal(harness.elements['#consent'].hidden, false);

      await harness.listeners.get(`${decision}:click`)();
      assert.deepEqual(
        harness.calls.filter(([name]) => name === decision).map(([, id]) => id),
        [authorizationId],
      );
      assert.equal(
        harness.assignments.at(-1),
        `https://provider.example/${decision === 'approve' ? 'approved' : 'denied'}-exact`,
      );
    });
  }
});

test('OAuth PKCE uses a cryptographic verifier, SHA-256, S256, and bounded state', () => {
  assert.match(source, /crypto\.getRandomValues/);
  assert.match(source, /crypto\.subtle\.digest\('SHA-256'/);
  assert.match(source, /code_challenge_method', 's256'/);
  assert.match(source, /requestId !== authorizationId/);
  assert.match(source, /GITHUB_MAX_AGE_MS/);
  assert.match(source, /SameSite=Lax; Secure/);
});

test('OAuth callback exchange rejects redirects and validates authenticated token response', () => {
  assert.match(source, /redirect: 'error'/);
  assert.match(source, /grant_type=pkce/);
  assert.match(source, /typeof payload\?\.access_token !== 'string'/);
  assert.match(source, /typeof payload\?\.refresh_token !== 'string'/);
  assert.match(source, /cleanCallbackUrl\(\)/);
});

test('consent remains authenticated and active-membership bound', () => {
  assert.match(source, /supabase\.auth\.getSession\(\)/);
  assert.match(source, /\/api\/operator\/session/);
  assert.match(source, /authorization: `Bearer \$\{current\.access_token\}`/);
  assert.match(source, /Active Pandoras-Box organization membership is required/);
});

test('client, scope, approval, and denial use Supabase authorization details', () => {
  assert.match(source, /getAuthorizationDetails\(authorizationId\)/);
  assert.match(source, /data\.client\?\.name/);
  assert.match(source, /data\.redirect_uri/);
  assert.match(source, /data\.scope/);
  assert.match(source, /approveAuthorization\(authorizationId\)/);
  assert.match(source, /denyAuthorization\(authorizationId\)/);
  assert.match(source, /window\.location\.assign\(data\.redirect_url\)/);
});

test('invalid or oversized authorization state fails before authentication', () => {
  assert.match(source, /!authorizationId \|\| authorizationId\.length > 2048/);
  assert.match(source, /authorization link is invalid or incomplete/);
});

test('consent document retains no-store delivery and explicit OAuth 2.1 PKCE disclosure', () => {
  assert.match(html, /OAuth 2\.1 \+ PKCE/);
  assert.match(html, /Durable plans, approvals, and execution/);
  assert.match(html, /Audit, account allowlists, destructive gate/);
});
