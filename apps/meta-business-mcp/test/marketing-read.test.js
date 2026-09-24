const assert = require('node:assert/strict');
const test = require('node:test');
const { OfficialMetaReadProvider } = require('../dist/meta/official-read-provider.js');
const { InMemorySecretResolver } = require('../dist/secrets/resolver.js');

test('Marketing reads use the marketing credential and return bounded aggregate data', async () => {
  const requests = [];
  const transport = {
    async send(request) {
      requests.push(request);
      const url = new URL(request.url);
      let body;
      if (url.pathname.endsWith('/me/adaccounts')) {
        body = { data: [{ id: 'act_123', account_id: '123', name: 'Main Ads', account_status: 1, currency: 'PHP' }] };
      } else if (url.pathname.endsWith('/act_123/campaigns')) {
        body = { data: [{ id: '456', name: 'Launch', status: 'ACTIVE', effective_status: 'ACTIVE', objective: 'OUTCOME_SALES' }] };
      } else if (url.pathname.endsWith('/act_123/insights')) {
        body = { data: [{ account_id: '123', account_name: 'Main Ads', account_currency: 'PHP', impressions: '1000', reach: '800', clicks: '50', spend: '100.00', ctr: '5.0', actions: [{ action_type: 'lead', value: '7' }], date_start: '2026-09-18', date_stop: '2026-09-25' }] };
      } else {
        throw new Error('unexpected test URL ' + request.url);
      }
      return { status: 200, bodyText: JSON.stringify(body), contentType: 'application/json' };
    },
  };
  const provider = new OfficialMetaReadProvider({
    apiVersion: 'v26.0',
    pageAccessTokenSecretRef: 'page-ref',
    marketingAccessTokenSecretRef: 'marketing-ref',
    secretResolver: new InMemorySecretResolver({ 'page-ref': 'page-token', 'marketing-ref': 'marketing-token' }),
    transport,
  });
  const accounts = await provider.listAdAccounts('999', 10);
  const campaigns = await provider.listCampaigns('999', 'act_123', 10);
  const insights = await provider.getAdAccountInsights('999', '123', 'last_7d');
  assert.equal(accounts[0].accountId, '123');
  assert.equal(campaigns[0].id, '456');
  assert.equal(insights[0].actions[0].actionType, 'lead');
  assert.equal(requests.length, 3);
  for (const request of requests) assert.equal(request.headers.authorization, 'Bearer marketing-token');
  assert.match(requests[2].url, /date_preset=last_7d/);
});

test('Marketing reads reject unbounded or malformed Meta identifiers and date presets', async () => {
  const provider = new OfficialMetaReadProvider({
    apiVersion: 'v26.0',
    pageAccessTokenSecretRef: 'page-ref',
    marketingAccessTokenSecretRef: 'marketing-ref',
    secretResolver: new InMemorySecretResolver({ 'page-ref': 'page-token', 'marketing-ref': 'marketing-token' }),
    transport: { async send() { throw new Error('network should not run'); } },
  });
  await assert.rejects(() => provider.listCampaigns('999', '../123', 10), /numeric Meta identifier/);
  await assert.rejects(() => provider.getAdAccountInsights('999', '123', 'forever'), /datePreset is unsupported/);
});
