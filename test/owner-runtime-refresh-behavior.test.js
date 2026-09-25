'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.resolve(__dirname, '..');
const source = fs.readFileSync(path.join(root, 'apps/control-tower/owner-runtime.js'), 'utf8');
const dataSource = fs.readFileSync(path.join(root, 'apps/control-tower/owner-data.js'), 'utf8');
// Exercise the production readiness predicate, not a permissive test substitute.
const readinessSource = dataSource.match(/function readiness\(candidate\) \{[\s\S]*?\n\}/)?.[0];
assert.ok(readinessSource, 'production readiness predicate is available');

const DEADLINE_MS = 12_000;
const paths = ['/status', '/health', '/tools', '/connections', '/metrics', '/plans?limit=100', '/logs?limit=100', '/logs/verify'];
const flush = () => new Promise((resolve) => setImmediate(resolve));
const pending = () => new Promise(() => {});
function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}
function response(data, status = 200) {
  return { ok: status >= 200 && status < 300, status, json: async () => data };
}
function fixtures() {
  return {
    '/status': { schemaVersion: '1.0.0', authoritative: true, status: 'current', expiresAt: '2099-01-01T00:00:00Z', tasks: [] },
    '/health': { status: 'healthy', protectedRoutesConfigured: true, durableLedgerConfigured: true, distributedRateLimitConfigured: true },
    '/tools': { tools: [] },
    '/connections': { connections: [{ id: 'fixture-connection' }] },
    '/metrics': { fixture: true },
    '/plans?limit=100': { plans: [{ id: 'fixture-plan', status: 'pending_approval' }] },
    '/logs?limit=100': { events: [{ id: 'fixture-event' }] },
    '/logs/verify': { verification: { valid: true } },
  };
}
function business(id = 'fixture-business') {
  return { contractVersion: 'pandora-owner-business-v1', observedAt: '2026-09-25T00:00:00Z', id };
}
function clock() {
  let now = 0;
  let nextId = 0;
  const timers = new Map();
  return {
    setTimeout(fn, delay) {
      const id = ++nextId;
      timers.set(id, { at: now + delay, fn });
      return id;
    },
    clearTimeout(id) { timers.delete(id); },
    size: () => timers.size,
    async tick(ms) {
      const target = now + ms;
      for (;;) {
        const next = [...timers].filter(([, timer]) => timer.at <= target).sort((a, b) => a[1].at - b[1].at)[0];
        if (!next) break;
        timers.delete(next[0]);
        now = next[1].at;
        next[1].fn();
        await flush();
      }
      now = target;
      await flush();
    },
  };
}
function harness(options = {}) {
  const timer = clock();
  const payloads = fixtures();
  const calls = [];
  const renders = [];
  const state = {
    projection: null, health: null, tools: null, connections: [], metrics: null, plans: [], logs: [], chain: null,
    business: { data: null, loading: false, error: null, loadedAt: null },
    session: { authenticated: true, email: 'fixture@example.invalid', role: 'owner' },
    live: false, loading: true, refreshing: false, error: null, toast: null,
  };
  const auth = {
    session: () => state.session,
    edgeRequest: (name, segments, init) => {
      calls.push({ path: 'business', name, segments, init });
      return options.business ? options.business() : Promise.resolve(business());
    },
  };
  if (options.missingBusiness) delete auth.edgeRequest;
  const data = {
    API_BASE: '/api/operator', state,
    rerender: () => renders.push({ live: state.live, business: state.business.data, businessLoading: state.business.loading }),
  };
  const context = vm.createContext({
    window: { PandorasOwnerData: data, MCPMasterAuth: auth },
    AbortController, Date, setTimeout: timer.setTimeout, clearTimeout: timer.clearTimeout,
    fetch: (url, init) => {
      const endpoint = url.replace('/api/operator', '');
      calls.push({ path: endpoint, init });
      return options.fetch ? options.fetch(endpoint, init, payloads) : Promise.resolve(response(payloads[endpoint]));
    },
  });
  data.readiness = vm.runInContext(`(${readinessSource})`, context);
  vm.runInContext(`(() => {\n${source}\n})();`, context, { filename: 'owner-runtime.js' });
  return { state, calls, renders, timer, runtime: context.window.PandorasOwnerRuntime, payloads };
}
async function begin(h, options = {}) {
  const observed = { settled: false, error: null };
  h.runtime.refresh(options).then(() => { observed.settled = true; }, (error) => { observed.error = error; observed.settled = true; });
  await flush();
  return observed;
}
function assertUnlocked(h, run) {
  assert.equal(run.error, null);
  assert.equal(run.settled, true, 'refresh promise settles within the read budget');
  assert.equal(h.state.refreshing, false);
  assert.equal(h.state.loading, false);
  assert.equal(h.state.business.loading, false);
}
function assertProtectedUnavailable(h) {
  assert.equal(h.state.live, false);
  for (const name of ['plans', 'connections', 'logs']) assert.equal(h.state[name].length, 0, `${name} stays fail-closed`);
  assert.ok(h.state.error);
}

test('successful refresh starts only bounded GET reads and clears all deadline timers', async () => {
  const h = harness();
  const run = await begin(h);
  assertUnlocked(h, run);
  assert.equal(h.state.live, true);
  assert.equal(h.state.error, null);
  assert.equal(h.state.business.data.id, 'fixture-business');
  assert.equal(h.state.plans.length, 1);
  assert.equal(h.calls.length, 9);
  for (const call of h.calls) {
    assert.equal(call.init.method || 'GET', 'GET');
    if (call.path !== 'business') {
      assert.equal(call.init.credentials, 'same-origin');
      assert.equal(call.init.cache, 'no-store');
      assert.equal(call.init.signal.aborted, false);
    }
  }
  assert.equal(h.timer.size(), 0);
});

for (const endpoint of paths) {
  for (const phase of ['fetch', 'body']) {
    test(`${endpoint} stalled ${phase} times out, unlocks refresh and retains independent Business data`, async () => {
      const h = harness({ fetch: (p, init, payloads) => {
        if (p !== endpoint) return Promise.resolve(response(payloads[p]));
        return phase === 'fetch' ? pending() : Promise.resolve({ ...response(null), json: pending });
      } });
      const run = await begin(h, { announce: true });
      assert.equal(run.settled, false);
      assert.equal(h.state.business.data?.id, 'fixture-business', 'Business renders before unrelated deadline');
      assert.equal(h.state.business.loading, false);
      await h.timer.tick(DEADLINE_MS);
      assertUnlocked(h, run);
      assertProtectedUnavailable(h);
      assert.equal(h.state.error.code, 'STATUS_TIMEOUT');
      assert.equal(h.state.toast.kind, 'error');
      assert.equal(h.calls.find((call) => call.path === endpoint).init.signal.aborted, true);
    });
  }
}

test('stalled Business cannot lock refresh or invalidate successful protected checks', async () => {
  const h = harness({ business: pending });
  const run = await begin(h, { announce: true });
  await h.timer.tick(DEADLINE_MS);
  assertUnlocked(h, run);
  assert.equal(h.state.live, true);
  assert.equal(h.state.business.data, null);
  assert.match(h.state.business.error, /timed out/i);
  assert.equal(h.state.toast.kind, 'error');
});

test('simultaneously stalled reads consume one budget, not serial projection and service budgets', async () => {
  const h = harness({ fetch: pending, business: pending });
  const run = await begin(h);
  assert.equal(h.calls.length, 9);
  await h.timer.tick(DEADLINE_MS - 1);
  assert.equal(run.settled, false);
  await h.timer.tick(1);
  assertUnlocked(h, run);
  assertProtectedUnavailable(h);
  assert.equal(h.timer.size(), 0);
});

for (const endpoint of paths) {
  test(`${endpoint} HTTP failure cannot discard a valid Business result or enable protected actions`, async () => {
    const h = harness({ fetch: (p, init, payloads) => Promise.resolve(p === endpoint
      ? response({ error: { code: 'HTTP_401', message: 'fixture-private-diagnostic' } }, 401)
      : response(payloads[p])) });
    const run = await begin(h, { announce: true });
    assertUnlocked(h, run);
    assertProtectedUnavailable(h);
    assert.equal(h.state.business.data.id, 'fixture-business');
    assert.equal(h.state.toast.kind, 'error');
    assert.doesNotMatch(h.state.error.message, /fixture-private-diagnostic/);
  });
}

const invalidReadiness = [
  ['expired projection', '/status', { expiresAt: '2000-01-01T00:00:00Z' }],
  ['non-authoritative projection', '/status', { authoritative: false }],
  ['stale projection', '/status', { status: 'stale' }],
  ['unhealthy service', '/health', { status: 'unhealthy' }],
  ['unprotected routes', '/health', { protectedRoutesConfigured: false }],
  ['missing durable ledger', '/health', { durableLedgerConfigured: false }],
  ['missing rate limiter', '/health', { distributedRateLimitConfigured: false }],
  ['invalid tools', '/tools', { tools: null }],
  ['missing connections', '/connections', { connections: null }],
  ['missing plans', '/plans?limit=100', { plans: null }],
  ['missing events', '/logs?limit=100', { events: null }],
  ['invalid audit chain', '/logs/verify', { verification: { valid: false } }],
];
for (const [label, endpoint, patch] of invalidReadiness) {
  test(`${label} never produces a success toast`, async () => {
    const h = harness({ fetch: (p, init, payloads) => Promise.resolve(response(p === endpoint ? { ...payloads[p], ...patch } : payloads[p])) });
    const run = await begin(h, { announce: true });
    assertUnlocked(h, run);
    assertProtectedUnavailable(h);
    assert.equal(h.state.toast.kind, 'error');
    assert.equal(h.state.business.data.id, 'fixture-business');
  });
}

test('projection schema rejection does not prevent other reads from starting', async () => {
  const h = harness({ fetch: (p, init, payloads) => Promise.resolve(response(p === '/status' ? {} : payloads[p])) });
  const run = await begin(h);
  assertUnlocked(h, run);
  assert.equal(h.calls.length, 9);
  assertProtectedUnavailable(h);
  assert.equal(h.state.business.data.id, 'fixture-business');
});

test('successful HTTP response with undecodable required JSON is not an empty live result', async () => {
  const h = harness({ fetch: (p, init, payloads) => Promise.resolve(p === '/connections'
    ? { ...response(null), json: async () => { throw new SyntaxError('fixture malformed JSON'); } }
    : response(payloads[p])) });
  const run = await begin(h, { announce: true });
  assertUnlocked(h, run);
  assertProtectedUnavailable(h);
  assert.equal(h.state.toast.kind, 'error');
});

for (const [label, options] of [
  ['missing Business transport', { missingBusiness: true }],
  ['invalid Business contract', { business: async () => ({ contractVersion: 'wrong' }) }],
  ['synchronous Business failure', { business: () => { throw new Error('fixture-sensitive-message'); } }],
  ['rejected Business read', { business: async () => { throw new Error('fixture-sensitive-message'); } }],
]) {
  test(`${label} remains a localized failure with no full-success announcement`, async () => {
    const h = harness(options);
    const run = await begin(h, { announce: true });
    assertUnlocked(h, run);
    assert.equal(h.state.live, true);
    assert.equal(h.state.business.data, null);
    assert.equal(h.state.business.loadedAt, null);
    assert.match(h.state.business.error, /try again/i);
    assert.doesNotMatch(h.state.business.error, /fixture-sensitive-message/);
    assert.equal(h.state.toast.kind, 'error');
  });
}

test('refresh is retryable after timeout and clears obsolete errors on success', async () => {
  let stalled = true;
  const h = harness({ fetch: (p, init, payloads) => p === '/status' && stalled ? pending() : Promise.resolve(response(payloads[p])) });
  const first = await begin(h, { announce: true });
  await h.timer.tick(DEADLINE_MS);
  assertUnlocked(h, first);
  stalled = false;
  const second = await begin(h, { announce: true });
  assertUnlocked(h, second);
  assert.equal(h.calls.filter((call) => call.path === '/status').length, 2);
  assert.equal(h.state.live, true);
  assert.equal(h.state.error, null);
  assert.equal(h.state.toast.kind, 'success');
});

test('a second refresh during an active read cannot start duplicate requests', async () => {
  const h = harness({ business: pending });
  const first = await begin(h);
  await h.runtime.refresh();
  assert.equal(h.calls.length, 9);
  await h.timer.tick(DEADLINE_MS);
  assertUnlocked(h, first);
});

test('late Business resolution after timeout cannot overwrite a newer successful result', async () => {
  const slow = deferred();
  let first = true;
  const h = harness({ business: () => first ? slow.promise : Promise.resolve(business('new-result')) });
  const oldRun = await begin(h);
  await h.timer.tick(DEADLINE_MS);
  assertUnlocked(h, oldRun);
  first = false;
  const newRun = await begin(h);
  assertUnlocked(h, newRun);
  slow.resolve(business('obsolete-result'));
  await flush();
  assert.equal(h.state.business.data.id, 'new-result');
});

test('late projection JSON after timeout cannot replace a newer projection', async () => {
  const slow = deferred();
  let first = true;
  const h = harness({ fetch: (p, init, payloads) => p === '/status' && first
    ? Promise.resolve({ ...response(null), json: () => slow.promise })
    : Promise.resolve(response({ ...payloads[p], fixtureId: 'new-result' })) });
  const oldRun = await begin(h);
  await h.timer.tick(DEADLINE_MS);
  assertUnlocked(h, oldRun);
  first = false;
  const newRun = await begin(h);
  assertUnlocked(h, newRun);
  slow.resolve({ ...fixtures()['/status'], fixtureId: 'obsolete-result' });
  await flush();
  assert.equal(h.state.projection.fixtureId, 'new-result');
});

test('late rejection from an abort-ignoring transport is observed, not unhandled', async () => {
  const slow = deferred();
  const h = harness({ business: () => slow.promise });
  const run = await begin(h);
  await h.timer.tick(DEADLINE_MS);
  assertUnlocked(h, run);
  slow.reject(new Error('fixture late failure'));
  await flush();
  assert.equal(h.state.business.data, null);
  assert.match(h.state.business.error, /timed out/);
});

test('auth state replacement prevents an in-flight Business read from restoring old-session data', async () => {
  const slow = deferred();
  const h = harness({ business: () => slow.promise });
  const run = await begin(h);
  h.state.business = { data: null, loading: false, error: null, loadedAt: null };
  h.state.session = { authenticated: false };
  slow.resolve(business('old-session'));
  await flush();
  assertUnlocked(h, run);
  assert.equal(h.state.business.data, null);
  assert.equal(h.state.live, false);
});

test('an older refresh cannot release a newer session refresh lock', async () => {
  const oldRead = deferred();
  const newRead = deferred();
  let old = true;
  const h = harness({ business: () => old ? oldRead.promise : newRead.promise });
  await begin(h);
  h.state.business = { data: null, loading: false, error: null, loadedAt: null };
  h.state.refreshing = false;
  old = false;
  const current = await begin(h);
  oldRead.resolve(business('old-session'));
  await flush();
  assert.equal(h.state.refreshing, true);
  assert.equal(h.state.business.loading, true);
  newRead.resolve(business('new-session'));
  await flush();
  assertUnlocked(h, current);
  assert.equal(h.state.business.data.id, 'new-session');
});

test('refresh deadlines do not change generic mutation request behavior or retry writes', async () => {
  const h = harness();
  await h.runtime.request('/fixture-mutation', { method: 'POST', body: '{}' });
  assert.equal(h.calls.length, 1);
  assert.equal(h.calls[0].init.method, 'POST');
  assert.equal(h.calls[0].init.signal, undefined);
  assert.equal(h.timer.size(), 0);
});
