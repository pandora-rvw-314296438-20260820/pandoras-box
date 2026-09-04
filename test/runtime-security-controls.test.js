const assert = require('node:assert/strict');
const test = require('node:test');

const { createHttpApp, executionPayloadHash } = require('../dist/http-app.js');
const {
  assertHighImpactPolicy,
  assertManifestConfirmation,
} = require('../dist/runtime/tool-manifest.js');
const { executeTool } = require('../dist/runtime/tool-catalog.js');

const ADMIN_TOKEN = 'admin-token-that-is-longer-than-thirty-two-characters';
const APPROVAL_TOKEN = 'approval-token-that-is-longer-than-thirty-two-chars';
const PLAN_ID = 'cfef1a79-1465-4c18-8180-563c4c397820';
const REQUEST_ID = 'e7928d0d-b112-4339-8a2b-16ff9e789ccb';

async function withServer(app, action) {
  const server = await new Promise((resolve) => {
    const value = app.listen(0, '127.0.0.1', () => resolve(value));
  });
  try {
    const address = server.address();
    return await action(`http://127.0.0.1:${address.port}`);
  } finally {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
  }
}

function runtime(ledger, toolExecutor) {
  const runtimeSecurity = {
    adminToken: ADMIN_TOKEN,
    approvalToken: APPROVAL_TOKEN,
    allowedOrigins: ['https://mcpmaster.vercel.app'],
  };
  return createHttpApp({
    port: 3000,
    adminToken: ADMIN_TOKEN,
    approvalToken: APPROVAL_TOKEN,
    allowedOrigins: 'https://mcpmaster.vercel.app',
    rateLimitRequests: 100,
    rateLimitWindowMs: 60_000,
  }, { async resolve() { return runtimeSecurity; } }, ledger, {
    async consume() { return { allowed: true, limit: 100, remaining: 99, count: 1, resetAt: new Date(Date.now() + 60_000).toISOString(), windowSeconds: 60 }; },
  }, async () => [], toolExecutor);
}

function protectedHeaders(extra = {}) {
  return {
    authorization: `Bearer ${ADMIN_TOKEN}`,
    'content-type': 'application/json',
    ...extra,
  };
}

test('durable execution rejects a claimed payload mismatch before provider execution', async () => {
  const ledger = {
    async claimPlan() {
      return {
        planId: PLAN_ID,
        requestId: REQUEST_ID,
        tool: 'github.get-repository',
        risk: 'read',
        args: { owner: 'banataosystems', repo: 'Pandoras-box' },
        payloadHash: '0'.repeat(64),
        status: 'executing',
      };
    },
    async finishPlan() { throw new Error('finish must not be reached'); },
  };
  await withServer(runtime(ledger), async (origin) => {
    const response = await fetch(`${origin}/tools/execute`, {
      method: 'POST',
      headers: protectedHeaders({ 'x-vercel-oidc-token': 'v'.repeat(80) }),
      body: JSON.stringify({ planId: PLAN_ID }),
    });
    const body = await response.json();
    assert.equal(response.status, 502);
    assert.match(body.error.message, /payload hash mismatch/);
  });
});

test('HTTP delete execution exposes only a ledger-proven reservation callback to provider dispatch', async () => {
  const args = {
    accountId: 'battle-realmatch',
    parentProjectRef: 'qjarspsifemjubmzsdgy',
    branchId: '11111111-1111-4111-8111-111111111111',
    childProjectRef: 'aaaaaaaaaaaaaaaaaaaa',
    deletionCapability: {
      schemaVersion: 'supabase-child-deletion-capability-v3',
      action: 'delete-and-reconcile-child-branch',
      signingKeyId: '2026-08-24-test-v1',
      reservationKeyId: 'child-delete-target-v1',
      accountId: 'battle-realmatch',
      organizationSlug: 'lqvpjqbgfodmtswxizwf',
      parentProjectRef: 'qjarspsifemjubmzsdgy',
      parentStatus: 'ACTIVE_HEALTHY',
      branchId: '11111111-1111-4111-8111-111111111111',
      childProjectRef: 'aaaaaaaaaaaaaaaaaaaa',
      operationNonce: 'ab'.repeat(32),
      issuedAt: '2026-08-24T12:00:00.000Z',
      deleteAuthorizationExpiresAt: '2026-08-24T12:10:00.000Z',
      reconciliationExpiresAt: '2026-08-31T12:00:00.000Z',
      membershipSnapshotSha256: 'cd'.repeat(32),
      proof: 'ef'.repeat(32),
    },
    confirmation: 'DELETE CHILD BRANCH qjarspsifemjubmzsdgy:11111111-1111-4111-8111-111111111111:aaaaaaaaaaaaaaaaaaaa',
  };
  const payloadHash = executionPayloadHash('supabase.delete-child-branch', args);
  let reservations = 0;
  let executions = 0;
  const ledger = {
    async claimPlan() {
      return {
        planId: PLAN_ID,
        requestId: REQUEST_ID,
        intakeId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        tool: 'supabase.delete-child-branch',
        risk: 'destructive',
        args,
        payloadHash,
        status: 'executing',
      };
    },
    async reserveCapability() { throw new Error('execution ledger reservation must not be used'); },
    async finishPlan(_token, input) {
      return { planId: input.planId, status: input.status };
    },
  };
  await withServer(runtime(ledger, async (tool, receivedArgs, context) => {
    executions += 1;
    assert.equal(tool, 'supabase.delete-child-branch');
    assert.equal(receivedArgs, args);
    assert.equal(typeof context.destructiveCapabilityReservation, 'function');
    const intent = await context.destructiveCapabilityReservation();
    reservations += 1;
    assert.equal(intent.payloadBinding.sourcePlanId, PLAN_ID);
    assert.equal(intent.payloadBinding.sourcePayloadHash, payloadHash);
    assert.equal(intent.payloadRedacted.targetDigest, intent.deliveryId);
    return { reserved: true };
  }), async (origin) => {
    const response = await fetch(`${origin}/tools/execute`, {
      method: 'POST',
      headers: protectedHeaders({ 'x-vercel-oidc-token': 'v'.repeat(80) }),
      body: JSON.stringify({ planId: PLAN_ID }),
    });
    const body = await response.json();
    assert.equal(response.status, 200);
    assert.deepEqual(body.result, { reserved: true });
  });
  assert.equal(reservations, 1);
  assert.equal(executions, 1);
});

test('write and destructive operations cannot bypass the separate durable plan action', async () => {
  const ledger = {};
  await withServer(runtime(ledger), async (origin) => {
    for (const tool of ['github.create-issue', 'github.merge-pull-request']) {
      const response = await fetch(`${origin}/tools/execute`, {
        method: 'POST',
        headers: protectedHeaders({ 'x-vercel-oidc-token': 'v'.repeat(80) }),
        body: JSON.stringify({ tool, args: {} }),
      });
      const body = await response.json();
      assert.equal(response.status, 409);
      assert.equal(body.error.code, 'PLAN_REQUIRED');
    }
  });
});

test('non-OIDC mutation execution requires the durable ledger despite a valid static approval token', async () => {
  const ledgerCalls = [];
  const executedTools = [];
  const ledger = new Proxy({}, {
    get(_target, property) {
      return async () => {
        ledgerCalls.push(String(property));
        throw new Error(`ledger ${String(property)} must not be reached`);
      };
    },
  });
  const app = runtime(ledger, async (tool) => {
    executedTools.push(tool);
    return { full_name: 'pandora-rvw-314296438-20260820/pandoras-box' };
  });

  await withServer(app, async (origin) => {
    const readResponse = await fetch(`${origin}/tools/execute`, {
      method: 'POST',
      headers: protectedHeaders(),
      body: JSON.stringify({
        tool: 'github.get-repository',
        args: { owner: 'banataosystems', repo: 'Pandoras-box' },
      }),
    });
    assert.equal(readResponse.status, 200);

    for (const tool of ['github.create-issue', 'github.merge-pull-request']) {
      const response = await fetch(`${origin}/tools/execute`, {
        method: 'POST',
        headers: protectedHeaders({ 'x-approval-token': APPROVAL_TOKEN }),
        body: JSON.stringify({ tool, args: {} }),
      });
      const body = await response.json();
      assert.equal(response.status, 503);
      assert.equal(body.error.code, 'DURABLE_LEDGER_REQUIRED');
    }
  });

  assert.deepEqual(ledgerCalls, []);
  assert.deepEqual(executedTools, ['github.get-repository']);
});

test('approval and execution are separate actions with exact server attribution', async () => {
  const calls = [];
  const ledger = {
    async approvePlan(token, planId, approver) {
      calls.push({ token, planId, approver });
      return { planId, requestId: REQUEST_ID, status: 'approved' };
    },
  };
  await withServer(runtime(ledger), async (origin) => {
    const response = await fetch(`${origin}/tools/approve`, {
      method: 'POST',
      headers: protectedHeaders({
        'x-vercel-oidc-token': 'v'.repeat(80),
        'x-approval-token': APPROVAL_TOKEN,
        'x-approver-id': 'supabase:verified-user',
      }),
      body: JSON.stringify({ planId: PLAN_ID }),
    });
    assert.equal(response.status, 200);
    assert.deepEqual(calls, [{ token: 'v'.repeat(80), planId: PLAN_ID, approver: 'supabase:verified-user' }]);
  });
});

test('operator approval rejects a substituted ledger plan identity or state', async () => {
  const ledger = {
    async approvePlan() {
      return {
        planId: '64368ef2-61b1-4586-8bdb-4d75fcbd5f77',
        requestId: REQUEST_ID,
        status: 'approved',
      };
    },
  };
  await withServer(runtime(ledger), async (origin) => {
    const response = await fetch(`${origin}/tools/approve`, {
      method: 'POST',
      headers: protectedHeaders({
        'x-vercel-oidc-token': 'v'.repeat(80),
        'x-approval-token': APPROVAL_TOKEN,
        'x-approver-id': 'supabase:verified-user',
      }),
      body: JSON.stringify({ planId: PLAN_ID }),
    });
    const body = await response.json();
    assert.equal(response.status, 409);
    assert.match(body.error.message, /mismatched plan identity or state/);
  });
});

test('operator execution rejects a substituted ledger plan identity or state', async () => {
  const ledger = {
    async claimPlan() {
      return {
        planId: '64368ef2-61b1-4586-8bdb-4d75fcbd5f77',
        requestId: REQUEST_ID,
        tool: 'github.get-repository',
        risk: 'read',
        args: { owner: 'banataosystems', repo: 'Pandoras-box' },
        payloadHash: executionPayloadHash('github.get-repository', { owner: 'banataosystems', repo: 'Pandoras-box' }),
        status: 'executing',
      };
    },
  };
  await withServer(runtime(ledger), async (origin) => {
    const response = await fetch(`${origin}/tools/execute`, {
      method: 'POST',
      headers: protectedHeaders({ 'x-vercel-oidc-token': 'v'.repeat(80) }),
      body: JSON.stringify({ planId: PLAN_ID }),
    });
    const body = await response.json();
    assert.equal(response.status, 409);
    assert.match(body.error.message, /mismatched plan identity or state/);
  });
});

test('execution payload hashes are canonical and bind tool plus exact arguments', () => {
  const left = executionPayloadHash('github.create-issue', { owner: 'banataosystems', repo: 'Pandoras-box', title: 'x' });
  const reordered = executionPayloadHash('github.create-issue', { title: 'x', repo: 'Pandoras-box', owner: 'banataosystems' });
  const changed = executionPayloadHash('github.create-issue', { owner: 'banataosystems', repo: 'Pandoras-box', title: 'y' });
  assert.equal(left, reordered);
  assert.notEqual(left, changed);
});

test('provider mutation, allowlist, scope, and confirmation controls stay enforced', async () => {
  const args = { owner: 'banataosystems', repo: 'Pandoras-box', title: 'x' };
  await assert.rejects(
    executeTool('github.create-issue', args, {
      github: {
        id: 'fixture', label: 'fixture', baseUrl: 'https://api.github.com', token: 'not-used',
        allowMutations: false, allowedRepositories: ['pandora-rvw-314296438-20260820/pandoras-box'], grantedScopes: ['issues:write'],
      },
    }),
    /mutations are disabled/i,
  );
  await assert.rejects(
    executeTool('github.create-issue', args, {
      github: {
        id: 'fixture', label: 'fixture', baseUrl: 'https://api.github.com', token: 'not-used',
        allowMutations: true, allowedRepositories: ['banataosystems/another'], grantedScopes: ['issues:write'],
      },
    }),
    /not allowed to access/i,
  );
  await assert.rejects(
    executeTool('github.create-issue', args, {
      github: {
        id: 'fixture', label: 'fixture', baseUrl: 'https://api.github.com', token: 'not-used',
        allowMutations: true, allowedRepositories: ['pandora-rvw-314296438-20260820/pandoras-box'], grantedScopes: [],
      },
    }),
    /missing required scope/i,
  );
  assert.throws(
    () => assertManifestConfirmation('github.delete-repository-api', {
      owner: 'banataosystems', repo: 'Pandoras-box', confirmation: 'DELETE wrong/repository',
    }),
    /Confirmation must exactly equal/,
  );
});

test('high-impact destructive actions remain behind the separate break-glass gate', () => {
  const args = {
    owner: 'pandora-rvw-314296438-20260820',
    repo: 'pandoras-box',
    pathSegments: [],
    confirmation: 'DELETE pandora-rvw-314296438-20260820/pandoras-box',
  };
  assertManifestConfirmation('github.delete-repository-api', args);
  assert.throws(() => assertHighImpactPolicy('github.delete-repository-api', args, false), /disabled by default/);
  assert.doesNotThrow(() => assertHighImpactPolicy('github.delete-repository-api', args, true));
});


test('Vercel OIDC GitHub control catalog outranks legacy GITHUB_TOKEN', async () => {
  const { buildToolConfiguration } = require('../dist/runtime/service-config.js');
  const envKeys = ['GITHUB_TOKEN','GITHUB_ALLOW_MUTATIONS','MCPMASTER_GITHUB_ACCOUNT_ID','VERCEL_OIDC_TOKEN'];
  const before = Object.fromEntries(envKeys.map((key) => [key, process.env[key]]));
  const originalFetch = globalThis.fetch;
  try {
    process.env.GITHUB_TOKEN = 'legacy-environment-token';
    delete process.env.GITHUB_ALLOW_MUTATIONS;
    process.env.MCPMASTER_GITHUB_ACCOUNT_ID = 'github-primary';
    delete process.env.VERCEL_OIDC_TOKEN;
    const calls = [];
    globalThis.fetch = async (url, options) => {
      calls.push({ url: String(url), options });
      return new Response(JSON.stringify({ ok: true, accounts: [{ id: 'github-primary', label: 'GitHub Account — banataosystems', authMode: 'pat', token: 'governed-vault-token', allowMutations: true, baseUrl: 'https://api.github.com', login: 'banataosystems', allowedRepositories: ['pandora-rvw-314296438-20260820/pandoras-box'], grantedScopes: ['identity:read'] }] }), { status: 200, headers: { 'content-type': 'application/json' } });
    };
    const configuration = await buildToolConfiguration('github.get-me', { vercelOidcToken: 'v'.repeat(80) });
    assert.equal(calls.length, 1);
    assert.equal(JSON.parse(calls[0].options.body).action, 'github_catalog');
    assert.equal(configuration.github.token, 'governed-vault-token');
    assert.equal(configuration.github.allowMutations, true);
  } finally {
    globalThis.fetch = originalFetch;
    for (const key of envKeys) {
      if (before[key] === undefined) delete process.env[key]; else process.env[key] = before[key];
    }
  }
});

test('legacy GITHUB_TOKEN remains available without OIDC', async () => {
  const { buildToolConfiguration } = require('../dist/runtime/service-config.js');
  const envKeys = ['GITHUB_TOKEN','GITHUB_ALLOW_MUTATIONS','MCPMASTER_GITHUB_ACCOUNT_ID','GITHUB_ALLOWED_REPOSITORIES','GITHUB_GRANTED_SCOPES','VERCEL_OIDC_TOKEN'];
  const before = Object.fromEntries(envKeys.map((key) => [key, process.env[key]]));
  try {
    process.env.GITHUB_TOKEN = 'legacy-environment-token';
    process.env.GITHUB_ALLOW_MUTATIONS = 'true';
    process.env.MCPMASTER_GITHUB_ACCOUNT_ID = 'github-primary';
    process.env.GITHUB_ALLOWED_REPOSITORIES = 'pandora-rvw-314296438-20260820/pandoras-box';
    process.env.GITHUB_GRANTED_SCOPES = 'identity:read';
    delete process.env.VERCEL_OIDC_TOKEN;
    const configuration = await buildToolConfiguration('github.get-me', {});
    assert.equal(configuration.github.token, 'legacy-environment-token');
    assert.equal(configuration.github.allowMutations, true);
  } finally {
    for (const key of envKeys) {
      if (before[key] === undefined) delete process.env[key]; else process.env[key] = before[key];
    }
  }
});
