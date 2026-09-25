'use strict';

// GROWTH-READ-BOUNDARY-TEST-001: actual production modules, synthetic transports.
// No live Meta access, provider writes, auth/RLS acceptance, consent or spend grant.
// The existing approved-ad-account/campaign binding gap is NOT repaired here.
const assert = require('node:assert/strict');
const test = require('node:test');
const { MetaNetworkReadExecutor } = require('../apps/meta-business-mcp/dist/tools/network-read-executor.js');
const { MetaReadDraftExecutor, MetaPolicyDeniedError, MetaWriteExecutionDisabledError } = require('../apps/meta-business-mcp/dist/tools/executor.js');
const { metaToolCatalog } = require('../apps/meta-business-mcp/dist/tools/catalog.js');
const { OfficialMetaReadProvider, MetaGraphApiError } = require('../apps/meta-business-mcp/dist/meta/official-read-provider.js');
const { InMemorySecretResolver } = require('../apps/meta-business-mcp/dist/secrets/resolver.js');

const PAGE = '999';
const PREFIX = 'Growth read boundary: ';
const context = (extra = {}) => ({
  organizationId: 'fixture-organization', staffId: 'fixture-staff',
  requesterId: 'fixture-requester', allowedPageIds: [PAGE],
  networkEnabled: true, killSwitchActive: false, ...extra,
});
const routes = [
  ['meta_page_get', 'getPage', {}, [PAGE]],
  ['meta_page_list_posts', 'listPosts', {}, [PAGE, 25]],
  ['meta_post_get', 'getPost', { postId: '999_100' }, [PAGE, '999_100']],
  ['meta_post_list_comments', 'listComments', { postId: '999_100' }, [PAGE, '999_100', 25]],
  ['meta_inbox_list_threads', 'listInboxThreads', {}, [PAGE, 25]],
  ['meta_inbox_get_thread', 'getInboxThread', { threadId: 'thread-100' }, [PAGE, 'thread-100']],
  ['meta_page_get_insights', 'getPageInsights', { metricNames: ['page_views_total'] }, [PAGE, ['page_views_total']]],
  ['meta_webhook_health', 'getWebhookHealth', {}, [PAGE]],
  ['meta_ad_accounts_list', 'listAdAccounts', {}, [PAGE, 25]],
  ['meta_ad_campaigns_list', 'listCampaigns', { adAccountId: '123' }, [PAGE, '123', 25]],
  ['meta_ad_account_insights', 'getAdAccountInsights', { adAccountId: '123' }, [PAGE, '123', 'last_7d']],
  ['meta_campaign_insights', 'getCampaignInsights', { campaignId: '456' }, [PAGE, '456', 'last_7d']],
];
function spyExecutor() {
  const calls = [];
  const provider = { providerKind: 'official-meta', networkCapable: true };
  for (const [, method] of routes) provider[method] = async (...args) => {
    calls.push({ method, args });
    return { fixtureMethod: method };
  };
  return { calls, provider, executor: new MetaNetworkReadExecutor(provider) };
}
function policyDenial(reason) {
  return (error) => error instanceof MetaPolicyDeniedError && error.reasons.includes(reason);
}

test(PREFIX + 'every catalogued read has an explicit dispatch and denial fixture', () => {
  assert.deepEqual(routes.map(([name]) => name).sort(), metaToolCatalog.filter((t) => t.mode === 'read').map((t) => t.name).sort());
  assert.ok(metaToolCatalog.some((t) => t.mode === 'write'));
  assert.ok(metaToolCatalog.some((t) => t.mode === 'draft'));
});

for (const tool of metaToolCatalog.filter((t) => t.mode === 'write')) {
  for (const kind of ['network', 'offline']) {
    test(PREFIX + `${kind} rejects ${tool.name} before reading arguments or approvals`, async () => {
      let touched = 0;
      const poison = new Proxy({}, { get() { touched += 1; throw new Error('unexpected boundary access'); } });
      const fixture = spyExecutor();
      const drafts = { async create() { touched += 1; throw new Error('unexpected draft write'); } };
      const executor = kind === 'network' ? fixture.executor
        : new MetaReadDraftExecutor({ ...fixture.provider, networkCapable: false }, drafts);
      await assert.rejects(() => executor.execute(tool.name, poison, poison), MetaWriteExecutionDisabledError);
      assert.equal(touched, 0);
      assert.equal(fixture.calls.length, 0);
    });
  }
}
for (const tool of metaToolCatalog.filter((t) => t.mode === 'draft')) {
  test(PREFIX + `network execution never promotes ${tool.name} to a provider action`, async () => {
    const fixture = spyExecutor();
    await assert.rejects(() => fixture.executor.execute(tool.name, { pageId: PAGE }, context()), policyDenial('network_executor_read_only'));
    assert.equal(fixture.calls.length, 0);
  });
}
for (const name of ['meta_campaign_create', 'meta_campaign_pause', 'meta_campaign_delete', 'meta_ad_budget_update', 'meta_publish_creative', 'not_a_meta_tool']) {
  test(PREFIX + `unknown action ${name} is denied even with claimed approval`, async () => {
    const fixture = spyExecutor();
    await assert.rejects(() => fixture.executor.execute(name, { pageId: PAGE, approved: true, dailyBudget: 100000 }, context({ approvalDecision: 'approved', approvedActionHash: 'a'.repeat(64) })), policyDenial('network_executor_read_only'));
    assert.equal(fixture.calls.length, 0);
  });
}

for (const [name, method, args, expected] of routes) {
  test(PREFIX + `${name} dispatches one read with the expected arguments`, async () => {
    const fixture = spyExecutor();
    const input = { pageId: PAGE, ...args };
    const result = await fixture.executor.execute(name, input, context());
    assert.deepEqual(fixture.calls, [{ method, args: expected }]);
    assert.equal(result.mode, 'read');
    assert.equal(result.toolName, name);
    assert.deepEqual(result.data, { fixtureMethod: method });
    assert.match(result.policy.actionHash, /^[a-f0-9]{64}$/);
    assert.deepEqual(input, { pageId: PAGE, ...args });
  });
  for (const [label, overrides, reason] of [
    ['network disabled', { networkEnabled: false }, 'meta_network_disabled'],
    ['Page outside allowlist', { allowedPageIds: ['other-page'] }, 'page_not_allowlisted'],
    ['empty Page allowlist', { allowedPageIds: [] }, 'page_not_allowlisted'],
    ['blank staff', { staffId: ' ' }, 'authenticated_staff_required'],
    ['blank requester', { requesterId: ' ' }, 'authenticated_staff_required'],
  ]) {
    test(PREFIX + `${name} rejects ${label} before calling the provider`, async () => {
      const fixture = spyExecutor();
      await assert.rejects(() => fixture.executor.execute(name, { pageId: PAGE, ...args }, context(overrides)), policyDenial(reason));
      assert.equal(fixture.calls.length, 0);
    });
  }
}

test(PREFIX + 'wildcard Page is not an allowlist grant', async () => {
  const fixture = spyExecutor();
  await assert.rejects(() => fixture.executor.execute('meta_page_get', { pageId: '*' }, context({ allowedPageIds: ['*'] })), policyDenial('page_not_allowlisted'));
  assert.equal(fixture.calls.length, 0);
});
test(PREFIX + 'write kill switch does not falsely disable an authorized read', async () => {
  const fixture = spyExecutor();
  const result = await fixture.executor.execute('meta_page_get', { pageId: PAGE }, context({ killSwitchActive: true }));
  assert.equal(result.mode, 'read');
  assert.equal(fixture.calls.length, 1);
});
test(PREFIX + 'audit output redacts nested synthetic sensitive fields', async () => {
  const fixture = spyExecutor();
  const result = await fixture.executor.execute('meta_page_get', {
    pageId: PAGE, metadata: { access_token: 'synthetic-canary-only', email: 'fixture@example.invalid', nested: { authorization: 'synthetic-header-only' } },
  }, context());
  assert.equal(result.audit.argumentsRedacted.metadata.access_token, '[REDACTED_SECRET]');
  assert.equal(result.audit.argumentsRedacted.metadata.email, '[REDACTED_PERSONAL]');
  assert.equal(result.audit.argumentsRedacted.metadata.nested.authorization, '[REDACTED_SECRET]');
  assert.doesNotMatch(JSON.stringify(result), /synthetic-canary-only|fixture@example\.invalid|synthetic-header-only/);
});

const limitRoutes = routes.filter(([, method]) => ['listPosts', 'listComments', 'listInboxThreads', 'listAdAccounts', 'listCampaigns'].includes(method));
for (const [name, , args] of limitRoutes) {
  for (const [label, limit] of [['zero', 0], ['negative', -1], ['over cap', 101], ['fraction', 1.5], ['numeric string', '25'], ['null', null]]) {
    test(PREFIX + `${name} rejects ${label} limit without a provider call`, async () => {
      const fixture = spyExecutor();
      await assert.rejects(() => fixture.executor.execute(name, { pageId: PAGE, ...args, limit }, context()), /limit must be an integer between 1 and 100/);
      assert.equal(fixture.calls.length, 0);
    });
  }
}
for (const [name, field] of [['meta_post_get', 'postId'], ['meta_post_list_comments', 'postId'], ['meta_inbox_get_thread', 'threadId'], ['meta_ad_campaigns_list', 'adAccountId'], ['meta_ad_account_insights', 'adAccountId'], ['meta_campaign_insights', 'campaignId']]) {
  for (const [label, value] of [['blank', ' '], ['non-string', 123]]) {
    test(PREFIX + `${name} rejects ${label} ${field}`, async () => {
      const fixture = spyExecutor();
      await assert.rejects(() => fixture.executor.execute(name, { pageId: PAGE, [field]: value }, context()), new RegExp(`${field} is required`));
      assert.equal(fixture.calls.length, 0);
    });
  }
}
for (const [label, metricNames] of [['string', 'page_views_total'], ['mixed array', ['page_views_total', 1]], ['null', null]]) {
  test(PREFIX + `Page metrics reject ${label}`, async () => {
    const fixture = spyExecutor();
    await assert.rejects(() => fixture.executor.execute('meta_page_get_insights', { pageId: PAGE, metricNames }, context()), /metricNames must be an array of strings/);
    assert.equal(fixture.calls.length, 0);
  });
}
for (const [label, provider] of [['offline provider', { providerKind: 'official-meta', networkCapable: false }], ['unapproved provider kind', { providerKind: 'fixture', networkCapable: true }]]) {
  test(PREFIX + `network constructor rejects ${label}`, () => {
    assert.throws(() => new MetaNetworkReadExecutor(provider), /official network-capable Meta provider/);
  });
}

// An official adapter driven solely by an in-memory transport. No global fetch is
// mocked, so no other parallel test's transport or module state is modified.
function officialFixture(response = { status: 200, body: { data: [] } }) {
  const requests = [], resolutions = [];
  const values = { 'fixture-page-ref': 'synthetic-page-only', 'fixture-marketing-ref': 'synthetic-marketing-only' };
  const memory = new InMemorySecretResolver(values);
  const provider = new OfficialMetaReadProvider({
    apiVersion: 'v26.0', pageAccessTokenSecretRef: 'fixture-page-ref',
    marketingAccessTokenSecretRef: 'fixture-marketing-ref', requestTimeoutMs: 5000,
    secretResolver: { async resolve(ref) { resolutions.push(ref); return memory.resolve(ref); } },
    transport: { async send(request) {
      requests.push(request);
      return { status: response.status, bodyText: response.raw ?? JSON.stringify(response.body), contentType: 'application/json' };
    } },
  });
  return { provider, requests, resolutions, executor: new MetaNetworkReadExecutor(provider) };
}

for (const [name, args, path] of [
  ['meta_ad_accounts_list', { limit: 10 }, '/v26.0/me/adaccounts'],
  ['meta_ad_campaigns_list', { adAccountId: 'act_123', limit: 10 }, '/v26.0/act_123/campaigns'],
  ['meta_ad_account_insights', { adAccountId: '123', datePreset: 'last_7d' }, '/v26.0/act_123/insights'],
  ['meta_campaign_insights', { campaignId: '456', datePreset: 'last_7d' }, '/v26.0/456/insights'],
]) {
  test(PREFIX + `${name} uses one GET and the marketing secret reference`, async () => {
    const fixture = officialFixture();
    const result = await fixture.executor.execute(name, { pageId: PAGE, ...args }, context());
    assert.deepEqual(fixture.resolutions, ['fixture-marketing-ref']);
    assert.equal(fixture.requests.length, 1);
    const request = fixture.requests[0], url = new URL(request.url);
    assert.equal(request.method, 'GET');
    assert.equal(url.origin, 'https://graph.facebook.com');
    assert.equal(url.pathname, path);
    assert.equal(url.searchParams.has('access_token'), false);
    assert.equal(request.headers.authorization, 'Bearer synthetic-marketing-only');
    assert.equal(request.timeoutMs, 5000);
    assert.equal(result.mode, 'read');
    assert.doesNotMatch(JSON.stringify(result), /synthetic-page-only|synthetic-marketing-only/);
  });
}
for (const badId of ['../123', '123/insights', '123?fields=secret', '123#fragment', '1e20', '-1']) {
  test(PREFIX + `official adapter rejects malformed asset ${badId} before secret resolution`, async () => {
    const fixture = officialFixture();
    await assert.rejects(() => fixture.executor.execute('meta_ad_campaigns_list', { pageId: PAGE, adAccountId: badId }, context()), /numeric Meta identifier/);
    assert.equal(fixture.requests.length, 0);
    assert.equal(fixture.resolutions.length, 0);
  });
}
test(PREFIX + 'unsupported report period cannot reach marketing credentials or transport', async () => {
  const fixture = officialFixture();
  await assert.rejects(() => fixture.executor.execute('meta_campaign_insights', { pageId: PAGE, campaignId: '456', datePreset: 'forever' }, context()), /datePreset is unsupported/);
  assert.equal(fixture.requests.length, 0);
  assert.equal(fixture.resolutions.length, 0);
});
for (const [label, response, code] of [
  ['expired credential', { status: 401, body: { error: { message: 'Synthetic expiry', code: 190 } } }, 190],
  ['missing permission', { status: 403, body: { error: { message: 'Synthetic denial', code: 10 } } }, 10],
  ['rate limit', { status: 429, body: { error: { message: 'Synthetic throttle', code: 4 } } }, 4],
  ['error in HTTP 200', { status: 200, body: { error: { message: 'Synthetic Graph error', code: 190 } } }, 190],
  ['server failure', { status: 500, body: {} }, undefined],
  ['invalid JSON', { status: 200, raw: '{' }, undefined],
]) {
  test(PREFIX + `${label} rejects rather than returning an empty success or retrying blindly`, async () => {
    const fixture = officialFixture(response);
    await assert.rejects(() => fixture.executor.execute('meta_ad_account_insights', { pageId: PAGE, adAccountId: '123' }, context()), (error) => {
      assert.ok(error instanceof MetaGraphApiError);
      assert.equal(error.details.httpStatus, response.status);
      assert.equal(error.details.code, code);
      return true;
    });
    assert.equal(fixture.requests.length, 1);
    assert.deepEqual(fixture.resolutions, ['fixture-marketing-ref']);
  });
}
test(PREFIX + 'explicit marketing identifiers, amounts and reporting context keep precision', async () => {
  const largeId = '900719925474099312345';
  const fixture = officialFixture({ status: 200, body: { data: [{
    account_id: largeId, campaign_id: '456', account_currency: 'PHP',
    spend: '123456789012345.67', impressions: '0', reach: '0', clicks: '0',
    actions: [{ action_type: 'lead', value: '7' }],
    action_values: [{ action_type: 'purchase', value: '5000.50' }],
    date_start: '2026-09-18', date_stop: '2026-09-25',
  }] } });
  const result = await fixture.executor.execute('meta_ad_account_insights', { pageId: PAGE, adAccountId: largeId }, context());
  const row = result.data[0];
  assert.equal(row.accountId, largeId);
  assert.equal(row.spend, '123456789012345.67');
  assert.equal(row.currency, 'PHP');
  assert.equal(row.impressions, '0');
  assert.equal(row.clicks, '0');
  assert.deepEqual(row.actions, [{ actionType: 'lead', value: '7' }]);
  assert.deepEqual(row.actionValues, [{ actionType: 'purchase', value: '5000.50' }]);
  assert.equal(row.dateStart, '2026-09-18');
  assert.equal(row.dateStop, '2026-09-25');
  assert.equal(row.cpc, undefined);
  assert.equal(new URL(fixture.requests[0].url).pathname, `/v26.0/act_${largeId}/insights`);
});
