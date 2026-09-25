'use strict';

// GROWTH-MEASUREMENT-INTEGRITY-001: built production adapter and executor,
// synthetic transport only. null is unavailable, never an observed zero.
// This does not certify paging completeness, tenant/asset binding or live Meta.
const assert = require('node:assert/strict');
const test = require('node:test');
const { OfficialMetaReadProvider, MetaGraphApiError } = require('../apps/meta-business-mcp/dist/meta/official-read-provider.js');
const { MetaNetworkReadExecutor } = require('../apps/meta-business-mcp/dist/tools/network-read-executor.js');
const { MetaPolicyDeniedError } = require('../apps/meta-business-mcp/dist/tools/executor.js');
const { InMemorySecretResolver } = require('../apps/meta-business-mcp/dist/secrets/resolver.js');

const PREFIX = 'Meta measurement integrity: ';
const metrics = ['impressions', 'reach', 'clicks', 'spend', 'cpc', 'cpm', 'ctr', 'frequency'];
const routes = [
  ['account', 'meta_ad_account_insights', { adAccountId: 'act_123' }, '/v26.0/act_123/insights'],
  ['campaign', 'meta_campaign_insights', { campaignId: '456' }, '/v26.0/456/insights'],
];
const context = {
  organizationId: 'fixture-organization', staffId: 'fixture-staff',
  requesterId: 'fixture-requester', allowedPageIds: ['999'],
  networkEnabled: true, killSwitchActive: false,
};
function values(value) {
  return Object.fromEntries(metrics.map((name) => [name, value]));
}
function fixture(body, status = 200) {
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
      return { status, bodyText: JSON.stringify(body), contentType: 'application/json' };
    } },
  });
  return { requests, provider, executor: new MetaNetworkReadExecutor(provider) };
}
async function execute(f, route) {
  const [, tool, args] = route;
  return f.executor.execute(tool, { pageId: '999', ...args, datePreset: 'last_7d' }, context);
}
function verifyRead(f, route) {
  assert.equal(f.requests.length, 1, 'exactly one bounded synthetic GET');
  const request = f.requests[0];
  const url = new URL(request.url);
  assert.equal(request.method, 'GET');
  assert.equal(url.origin, 'https://graph.facebook.com');
  assert.equal(url.pathname, route[3]);
  assert.equal(url.searchParams.get('limit'), '100');
  assert.equal(url.searchParams.get('date_preset'), 'last_7d');
  assert.equal(url.searchParams.has('access_token'), false);
  assert.equal(request.headers.authorization, 'Bearer synthetic-marketing-canary');
}
function assertMetrics(row, expected) {
  for (const key of metrics) {
    assert.ok(Object.hasOwn(row, key), `${key} must remain explicit`);
    assert.equal(row[key], expected, key);
  }
  const wire = JSON.parse(JSON.stringify(row));
  for (const key of metrics) assert.equal(wire[key], expected, `${key} after JSON`);
}

for (const route of routes) {
  for (const [label, input] of [
    ['omitted', undefined], ['null', null], ['empty string', ''], ['whitespace', ' \t '],
    ['boolean', false], ['object', {}], ['array', []], ['nonnumeric', 'not-a-number'],
    ['NaN text', 'NaN'], ['infinity text', 'Infinity'], ['hex text', '0x10'],
    ['locale separators', '1,000'], ['malformed decimal', '1.2.3'], ['malformed exponent', '1e'],
    ['malformed sign', '--1'],
  ]) {
    test(PREFIX + `${route[0]} ${label} metrics remain unavailable, not zero`, async () => {
      const f = fixture({ data: [values(input)] });
      const result = await execute(f, route);
      assert.equal(result.mode, 'read');
      assert.equal(result.data.length, 1);
      assertMetrics(result.data[0], null);
      assert.equal(result.data[0].actions, null);
      assert.equal(result.data[0].actionValues, null);
      verifyRead(f, route);
    });
  }
  for (const [label, input, expected] of [
    ['string zero', '0', '0'], ['numeric zero', 0, '0'], ['decimal zero', '0.0000', '0.0000'],
    ['precise decimal', '0.100000000000000001', '0.100000000000000001'],
    ['numeric fraction', 0.125, '0.125'],
    ['large decimal string', '90071992547409931234567890123.123456789', '90071992547409931234567890123.123456789'],
    ['signed reported value', '-0.25', '-0.25'], ['signed numeric value', -2.5, '-2.5'],
    ['scientific string', '1e-8', '1e-8'], ['numeric exponent', 1e-7, '1e-7'],
    ['trimmed string without requantization', ' 001.2300 ', '001.2300'],
    ['largest safe integer', Number.MAX_SAFE_INTEGER, String(Number.MAX_SAFE_INTEGER)],
  ]) {
    test(PREFIX + `${route[0]} preserves ${label}`, async () => {
      const f = fixture({ data: [values(input)] });
      const result = await execute(f, route);
      assertMetrics(result.data[0], expected);
      verifyRead(f, route);
    });
  }
  test(PREFIX + `${route[0]} rejects an unsafe numeric integer instead of inventing precision`, async () => {
    const f = fixture({ data: [values(Number.MAX_SAFE_INTEGER + 1)] });
    assertMetrics((await execute(f, route)).data[0], null);
    verifyRead(f, route);
  });
  test(PREFIX + `${route[0]} keeps sparse observations and identities independent`, async () => {
    const body = { data: [{
      account_id: '9007199254740993123', campaign_id: '9007199254740993456',
      account_currency: 'PHP', date_start: '2026-09-18', date_stop: '2026-09-24',
      impressions: '0', clicks: '3', spend: '0.00', cpc: null,
    }] };
    const before = JSON.stringify(body);
    const f = fixture(body);
    const result = await execute(f, route);
    const row = result.data[0];
    assert.equal(row.accountId, body.data[0].account_id);
    assert.equal(row.campaignId, body.data[0].campaign_id);
    assert.equal(row.currency, 'PHP');
    assert.equal(row.dateStart, '2026-09-18');
    assert.equal(row.dateStop, '2026-09-24');
    assert.equal(row.impressions, '0');
    assert.equal(row.clicks, '3');
    assert.equal(row.spend, '0.00');
    assert.equal(row.reach, null);
    assert.equal(row.cpc, null);
    assert.equal(row.ctr, null, 'do not derive a rate from sparse observations');
    assert.equal(row.actions, null);
    assert.equal(JSON.stringify(body), before, 'input body must not be mutated');
    assert.doesNotMatch(JSON.stringify(result), /synthetic-(?:page|marketing)-canary/);
    verifyRead(f, route);
  });
  for (const [label, input] of [
    ['omitted', undefined], ['null', null], ['boolean', true], ['empty object', {}],
    ['string', '[]'], ['malformed wrapper', { data: '[]' }],
  ]) {
    test(PREFIX + `${route[0]} ${label} action collections are unavailable, not empty`, async () => {
      const f = fixture({ data: [{ actions: input, action_values: input }] });
      const row = (await execute(f, route)).data[0];
      assert.equal(row.actions, null);
      assert.equal(row.actionValues, null);
      assert.deepEqual(JSON.parse(JSON.stringify(row)).actions, null);
      verifyRead(f, route);
    });
  }
  for (const wrapped of [false, true]) {
    test(PREFIX + `${route[0]} explicit ${wrapped ? 'wrapped ' : ''}empty action collections remain observed empty`, async () => {
      const input = wrapped ? { data: [] } : [];
      const f = fixture({ data: [{ actions: input, action_values: input }] });
      const row = (await execute(f, route)).data[0];
      assert.deepEqual(row.actions, []);
      assert.deepEqual(row.actionValues, []);
      verifyRead(f, route);
    });
  }
  test(PREFIX + `${route[0]} preserves incomplete action rows without fabricated quantities or labels`, async () => {
    const actions = [
      { action_type: 'lead', value: '0' }, { action_type: 'purchase' },
      { value: '1' }, { action_type: 'message', value: null },
      { action_type: 'call', value: 'invalid' }, null,
      { action_type: 'unknown', value: 0.25 },
    ];
    const expected = [
      { actionType: 'lead', value: '0' }, { actionType: 'purchase', value: null },
      { actionType: null, value: '1' }, { actionType: 'message', value: null },
      { actionType: 'call', value: null }, { actionType: null, value: null },
      { actionType: 'unknown', value: '0.25' },
    ];
    const f = fixture({ data: [{ actions, action_values: { data: actions } }] });
    const row = (await execute(f, route)).data[0];
    assert.deepEqual(row.actions, expected);
    assert.deepEqual(row.actionValues, expected);
    assert.deepEqual(JSON.parse(JSON.stringify(row)).actions, expected);
    verifyRead(f, route);
  });
  test(PREFIX + `${route[0]} keeps action counts separate from monetary values with no coercion or aggregation`, async () => {
    const f = fixture({ data: [{
      actions: [{ action_type: 'purchase', value: '1' }],
      action_values: [{ action_type: 'purchase', value: '9007199254740993.000001' }],
      spend: '0.000001', account_currency: 'PHP',
    }] });
    const row = (await execute(f, route)).data[0];
    assert.deepEqual(row.actions, [{ actionType: 'purchase', value: '1' }]);
    assert.deepEqual(row.actionValues, [{ actionType: 'purchase', value: '9007199254740993.000001' }]);
    assert.equal(row.spend, '0.000001');
    assert.equal(Object.hasOwn(row, 'roas'), false);
    verifyRead(f, route);
  });
  test(PREFIX + `${route[0]} missing identity and period stay unassigned`, async () => {
    const f = fixture({ data: [{}] });
    const row = (await execute(f, route)).data[0];
    for (const key of ['accountId', 'campaignId', 'currency', 'dateStart', 'dateStop']) {
      assert.equal(row[key], undefined);
    }
    assertMetrics(row, null);
    verifyRead(f, route);
  });
  test(PREFIX + `${route[0]} explicit empty report stays empty without a synthetic zero row`, async () => {
    const f = fixture({ data: [] });
    assert.deepEqual((await execute(f, route)).data, []);
    verifyRead(f, route);
  });
  test(PREFIX + `${route[0]} provider error is not normalized into missing or zero data`, async () => {
    const f = fixture({ error: { message: 'synthetic permission failure', code: 190 } });
    await assert.rejects(() => execute(f, route), MetaGraphApiError);
    verifyRead(f, route);
  });
  test(PREFIX + `${route[0]} Page denial still occurs before transport`, async () => {
    const f = fixture({ data: [values('0')] });
    const [, tool, args] = route;
    await assert.rejects(() => f.executor.execute(tool, { pageId: '888', ...args }, context), MetaPolicyDeniedError);
    assert.equal(f.requests.length, 0);
  });
}

test(PREFIX + 'direct normalization rejects non-finite and unsafe numeric observations', () => {
  const f = fixture({ data: [] });
  for (const input of [NaN, Infinity, -Infinity, Number.MAX_SAFE_INTEGER + 1, -(Number.MAX_SAFE_INTEGER + 1)]) {
    const row = f.provider.mapMarketingInsight({ ...values(input), actions: [{ action_type: 'lead', value: input }] });
    assertMetrics(row, null);
    assert.deepEqual(row.actions, [{ actionType: 'lead', value: null }]);
  }
  assert.equal(f.requests.length, 0);
});
