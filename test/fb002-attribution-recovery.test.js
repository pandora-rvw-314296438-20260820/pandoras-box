const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const read = (file) => fs.readFileSync(path.join(__dirname, '..', file), 'utf8');

test('FB-002 preserves provider history without replaying stale ProjectOS authority', () => {
  for (const file of [
    'supabase/migrations/20260921100623_pandora_tracking_owner_scope_and_currency_safe_reporting_v2.sql',
    'supabase/migrations/20260921100805_pandora_tracking_traffic_daily_dedup_fix_v2.sql',
  ]) {
    const source = read(file);
    assert.match(source, /history_receipt_noop/);
    assert.match(source, /20260925072000_pandora_tracking_dashboard_recovery_v1\.sql/);
    assert.match(source, /select 1;/);
  }
});

test('FB-002 forward repair uses Pandora project authority and preserves reporting truth', () => {
  const source = read('supabase/migrations/20260925072000_pandora_tracking_dashboard_recovery_v1.sql');
  assert.match(source, /references public\.pandora_projects\(id\)/);
  assert.doesNotMatch(source, /references public\.projectos_projects\(id\)/);
  assert.match(source, /pandora_tracking_validate_tenant_scope_v2/);
  assert.match(source, /pandora_tracking_campaign_traffic_daily_v2/);
  assert.match(source, /pandora_tracking_campaign_financial_daily_v2/);
  assert.match(source, /count\(distinct visitor_hash\)/);
  assert.match(source, /roas/);
  assert.match(source, /revoke all .*anon, authenticated/s);
  assert.match(source, /grant select .*service_role/s);
});

test('FB-002 records a disposition for every PR 682 changed file', () => {
  const evidence = JSON.parse(read('docs/recovery/FB002_PR682_ATTRIBUTION_RECOVERY_20260925.json'));
  assert.equal(evidence.taskId, 'FB-002');
  assert.equal(evidence.sourcePullRequest, 682);
  assert.equal(evidence.staleHeadSha, 'd68397fd843e22133ea50f25f2fc1540d78eba9d');
  assert.equal(evidence.disposition.length, 15);
  assert.equal(new Set(evidence.disposition.map((item) => item.path)).size, 15);
  assert.equal(evidence.boundaries.visibleDashboardActivated, false);
  assert.equal(evidence.boundaries.projectosRuntimeAuthorityRestored, false);
});

test('FB-002 does not lose already-recovered tracking HTTP aliases', () => {
  const source = read('src/pandora-tracking-http.js');
  for (const route of ['/tracking/health','/tracking/event','/tracking/conversion','/tracking/cost','/tracking/report','/api/tracking/health']) {
    assert.ok(source.includes(route), route + ' must remain available');
  }
});
