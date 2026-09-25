'use strict';

// GROWTH-REPORT-ENVELOPE-001: production adapter/executor, synthetic transport.
// No live Meta access, full pagination, tenant binding or ROAS certification.
const assert = require('node:assert/strict');
const test = require('node:test');
const { OfficialMetaReadProvider, MetaGraphApiError } = require('../apps/meta-business-mcp/dist/meta/official-read-provider.js');
const { MetaNetworkReadExecutor } = require('../apps/meta-business-mcp/dist/tools/network-read-executor.js');
const { MetaPolicyDeniedError } = require('../apps/meta-business-mcp/dist/tools/executor.js');
const { InMemorySecretResolver } = require('../apps/meta-business-mcp/dist/secrets/resolver.js');

const PREFIX = 'Meta report envelope: ';
const routes = [
  { name: 'accounts', tool: 'meta_ad_accounts_list', args: { limit: 10 }, path: '/v26.0/me/adaccounts', report: false },
  { name: 'campaigns', tool: 'meta_ad_campaigns_list', args: { adAccountId: 'act_123', limit: 10 }, path: '/v26.0/act_123/campaigns', report: false },
  { name: 'account insights', tool: 'meta_ad_account_insights', args: { adAccountId: 'act_123', datePreset: 'last_7d' }, path: '/v26.0/act_123/insights', report: true },
  { name: 'campaign insights', tool: 'meta_campaign_insights', args: { campaignId: '456', datePreset: 'last_7d' }, path: '/v26.0/456/insights', report: true },
];
const context = {
  organizationId: 'fixture-organization', staffId: 'fixture-staff',
  requesterId: 'fixture-requester', allowedPageIds: ['999'],
  networkEnabled: true, killSwitchActive: false,
};
function fixture(body, { status = 200, raw, failure } = {}) {
  const requests = [];
  const provider = new OfficialMetaReadProvider({
    apiVersion: 'v26.0', pageAccessTokenSecretRef: 'fixture-page-ref',
    marketingAccessTokenSecretRef: 'fixture-marketing-ref',
    secretResolver: new InMemorySecretResolver({
      'fixture-page-ref': 'synthetic-page-canary',
      'fixture-marketing-ref': 'synthetic-marketing-canary',
    }),
    transport: { async send(request) {
      requests.push(request);
      if (failure) throw failure;
      return { status, bodyText: raw === undefined ? JSON.stringify(body) : raw, contentType: 'application/json' };
    } },
  });
  return { requests, provider, executor: new MetaNetworkReadExecutor(provider) };
}
async function execute(f, route, overrides = {}) {
  return f.executor.execute(route.tool, { pageId: '999', ...route.args }, { ...context, ...overrides });
}
function verifyRead(f, route) {
  assert.equal(f.requests.length, 1, 'one bounded request, no implicit retry or next-page fetch');
  const request = f.requests[0];
  const url = new URL(request.url);
  assert.equal(request.method, 'GET');
  assert.equal(url.origin, 'https://graph.facebook.com');
  assert.equal(url.pathname, route.path);
  assert.equal(url.searchParams.get('limit'), route.report ? '100' : '10');
  if (route.report) assert.equal(url.searchParams.get('date_preset'), 'last_7d');
  assert.equal(url.searchParams.has('access_token'), false);
  assert.equal(url.searchParams.has('after'), false);
  assert.equal(request.headers.authorization, 'Bearer synthetic-marketing-canary');
}
async function rejected(f, route, reason, status = 200) {
  await assert.rejects(() => execute(f, route), (error) => {
    assert.ok(error instanceof MetaGraphApiError, 'typed failure, not incidental TypeError or successful data');
    assert.equal(error.details.reason, reason);
    assert.equal(error.details.httpStatus, status);
    assert.doesNotMatch(error.message + JSON.stringify(error.details), /synthetic-(?:page|marketing)-canary|untrusted\.invalid|access_token|opaque-fixture-cursor/);
    assert.equal(Object.hasOwn(error, 'data'), false, 'no successful partial rows attached');
    return true;
  });
  verifyRead(f, route);
}
const invalidCollections = [
  ['null root', null], ['bare array', []], ['string root', 'synthetic-marketing-canary'],
  ['numeric root', 0], ['boolean root', false], ['missing data', {}],
  ['null data', { data: null }], ['object data', { data: {} }],
  ['string data', { data: '[]' }], ['numeric data', { data: 0 }], ['boolean data', { data: false }],
];
const invalidPaging = [
  ['null paging', null], ['array paging', []], ['string paging', 'synthetic-marketing-canary'],
  ['null next', { next: null }], ['empty next', { next: '' }], ['blank next', { next: '  ' }],
  ['numeric next', { next: 7 }], ['boolean next', { next: false }], ['object next', { next: {} }],
  ['null cursors', { cursors: null }], ['array cursors', { cursors: [] }],
  ['numeric after', { cursors: { after: 7 } }], ['empty before', { cursors: { before: '' } }],
];
for (const route of routes) {
  for (const [label, body] of invalidCollections) {
    test(PREFIX + `${route.name} rejects ${label} instead of empty`, async () => {
      await rejected(fixture(body), route, 'invalid_collection_envelope');
    });
  }
  for (const [label, row] of [['null', null], ['array', []], ['string', 'synthetic-marketing-canary'], ['number', 5], ['boolean', true]]) {
    test(PREFIX + `${route.name} rejects ${label} row without silently dropping or replacing it`, async () => {
      await rejected(fixture({ data: [{}, row, {}] }), route, 'invalid_collection_rows');
    });
  }
  for (const [label, paging] of invalidPaging) {
    test(PREFIX + `${route.name} rejects ${label}`, async () => {
      await rejected(fixture({ data: [], paging }), route, 'invalid_paging_envelope');
    });
  }
  for (const [label, metadata] of [
    ['no paging', {}], ['empty paging', { paging: {} }],
    ['terminal cursors', { paging: { cursors: { before: 'first', after: 'last' } } }],
  ]) {
    test(PREFIX + `${route.name} preserves explicit empty with ${label}`, async () => {
      const f = fixture({ data: [], ...metadata });
      const result = await execute(f, route);
      assert.equal(result.mode, 'read');
      assert.deepEqual(result.data, []);
      assert.deepEqual(JSON.parse(JSON.stringify(result)).data, []);
      assert.equal(Object.hasOwn(result, 'complete'), false, 'guard does not certify reporting coverage');
      verifyRead(f, route);
    });
  }
  test(PREFIX + `${route.name} invalid JSON remains a typed error`, async () => {
    await rejected(fixture(null, { raw: '{invalid synthetic-marketing-canary' }), route, undefined);
  });
  for (const status of [200, 403, 429]) {
    test(PREFIX + `${route.name} Graph error at HTTP ${status} is never a report`, async () => {
      const f = fixture({ data: [], error: { message: 'Synthetic provider refusal', code: 190 } }, { status });
      await assert.rejects(() => execute(f, route), (error) => {
        assert.ok(error instanceof MetaGraphApiError);
        assert.equal(error.details.httpStatus, status);
        assert.equal(error.details.code, 190);
        return true;
      });
      verifyRead(f, route);
    });
  }
  test(PREFIX + `${route.name} HTTP failure with null body is typed`, async () => {
    await rejected(fixture(null, { status: 503 }), route, undefined, 503);
  });
  for (const [label, overrides] of [['Page denied', { allowedPageIds: [] }], ['network disabled', { networkEnabled: false }]]) {
    test(PREFIX + `${route.name} ${label} is rejected before transport`, async () => {
      const f = fixture({ data: [] });
      await assert.rejects(() => execute(f, route, overrides), MetaPolicyDeniedError);
      assert.equal(f.requests.length, 0);
    });
  }
}
const continuations = [
  ['provider URL', 'https://graph.facebook.com/v26.0/act_123/insights?after=opaque-fixture-cursor'],
  ['foreign token URL', 'https://untrusted.invalid/other?access_token=synthetic-marketing-canary'],
  ['cross-asset URL', 'https://graph.facebook.com/v26.0/789/insights?date_preset=today'],
  ['opaque marker', 'opaque-fixture-cursor'],
];
for (const route of routes.filter((value) => value.report)) {
  for (const [label, next] of continuations) {
    test(PREFIX + `${route.name} refuses ${label} continuation without following or exposing it`, async () => {
      await rejected(fixture({ data: [{ spend: '123.4500' }], paging: { next } }), route, 'incomplete_report');
    });
  }
  test(PREFIX + `${route.name} empty page with continuation is not empty report`, async () => {
    await rejected(fixture({ data: [], paging: { next: 'opaque-fixture-cursor' } }), route, 'incomplete_report');
  });
  test(PREFIX + `${route.name} page at limit without next preserves rows without fabricated coverage`, async () => {
    const body = { data: Array.from({ length: 100 }, () => ({
      account_id: '123', campaign_id: '456', account_currency: 'PHP',
      spend: '9007199254740993.000001', clicks: '0',
      date_start: '2026-09-18', date_stop: '2026-09-24',
    })) };
    const before = JSON.stringify(body);
    const f = fixture(body);
    const result = await execute(f, route);
    assert.equal(result.data.length, 100, 'no arbitrary deduplication or summation');
    assert.equal(result.data[0].spend, '9007199254740993.000001');
    assert.equal(result.data[0].clicks, '0');
    assert.equal(result.data[0].impressions, null);
    assert.equal(result.data[0].actions, null);
    assert.equal(result.data[0].currency, 'PHP');
    assert.equal(result.data[0].dateStart, '2026-09-18');
    assert.equal(result.data[0].dateStop, '2026-09-24');
    assert.equal(JSON.stringify(body), before);
    assert.doesNotMatch(JSON.stringify(result), /synthetic-(?:page|marketing)-canary/);
    verifyRead(f, route);
  });
  test(PREFIX + `${route.name} cancellation does not become empty or trigger retry`, async () => {
    const abort = new Error('synthetic cancellation');
    abort.name = 'AbortError';
    const f = fixture(null, { failure: abort });
    await assert.rejects(() => execute(f, route), (error) => error === abort);
    verifyRead(f, route);
  });
}
for (const route of routes.filter((value) => !value.report)) {
  test(PREFIX + `${route.name} intentional limited listing is not automatically traversed`, async () => {
    const f = fixture({ data: [{ id: '456', name: 'Fixture' }], paging: {
      next: 'https://untrusted.invalid/other?access_token=synthetic-marketing-canary',
      cursors: { after: 'opaque-fixture-cursor' },
    } });
    const result = await execute(f, route);
    assert.equal(result.data.length, 1);
    assert.equal(result.data[0].id, '456');
    assert.equal(Object.hasOwn(result, 'complete'), false);
    assert.doesNotMatch(JSON.stringify(result), /untrusted\.invalid|access_token|opaque-fixture-cursor|synthetic-marketing-canary/);
    verifyRead(f, route);
  });
}
